`timescale 1ns/1ps

//==============================================================================
// tb_matrix_3x3_gen: complete self-checking regression, all cases run automatically.
// Every output beat is compared with the 3x3 windows of the source image;
// window positions outside the image are not checked (padding is a later stage).
// Drive with nonblocking assignments and sample only on the rising clock edge.
//==============================================================================
module tb_matrix_3x3_gen #(
    parameter integer  TAP        = 8   ,//pixels per beat, power of 2
    parameter integer  PIX        = 10  ,//bits per pixel
    parameter integer  UW         = 4   ,//0:SOF 1:SOL 2:EOL 3:EOF
    parameter integer  LINE_BEATS = 8   ,//beats per line, at least 4
    parameter integer  HEIGHT     = 6   ,//lines per frame                
    parameter integer  LINE_GAP   = 16  ,//unit: enabled clocks between two lines
    parameter integer  LINE_MAX   = 2048,//unit: pixels, DUT line buffer depth
    parameter realtime PIXEL_HALF = 3.5
);

    `include "define_isp.sv"

    localparam integer DW          = TAP * PIX;
    localparam integer WIDTH       = TAP * LINE_BEATS;
    localparam integer FRAME_GAP   = 2*LINE_GAP + LINE_BEATS + 32;//covers the DUT flush of the last line
    localparam integer FRAME_NUM   = 3;                           //frames per case
    localparam integer CASE_NUM    = 7;
    localparam integer WAIT_LIMIT  = 12000;
    localparam integer PRINT_LIMIT = 6;                           //printed errors per case, the rest is only counted
    localparam integer ERROR_LIMIT = 4000;
    localparam integer SEED        = 32'h4e4f5609;
    //tvalid inside a line
    localparam integer GAP_NONE    = 0;                           //continuous
    localparam integer GAP_ONE     = 1;                           //one idle clock before beat gap_beat of every line
    localparam integer GAP_RANDOM  = 2;                           //0..3 idle clocks before every beat

    logic                                clk                     = 0;
    logic                                rst_n                   = 0;
    logic                                s_valid                 = 0;
    logic                                s_ready                 ;
    logic         [TAP-1:0][PIX-1:0]     s_data                  = 0;
    logic         [UW-1:0]               s_user                  = 0;
    logic                                m_ready                 = 0;
    logic                                m_valid                 ;
    logic         [TAP-1:0][8:0][PIX-1:0] m_data                 ;
    logic         [UW-1:0]               m_user                  ;
    logic         [15:0]                 width_cfg               = WIDTH;
    logic         [15:0]                 height_cfg              = HEIGHT;
    typedef struct packed {
        logic         [TAP-1:0][8:0][PIX-1:0] data      ;
        logic         [TAP-1:0][8:0]          mask      ;//1: inside the image, compared
        logic         [UW-1:0]                user_bits ;
        logic         [15:0]                  frame_id  ;
        logic         [15:0]                  line_id   ;
        logic         [15:0]                  beat_id   ;
    } expected_t;
    expected_t expected[$];
    integer                              errors                  = 0;
    integer                              cycles                  = 0;
    integer                              sent                    = 0;
    integer                              received                = 0;
    integer                              gaps                    = 0;
    integer                              case_start_errors       = 0;
    integer                              case_errors[CASE_NUM]   ;
    integer                              case_sent[CASE_NUM]     ;
    integer                              case_received[CASE_NUM] ;
    integer                              case_gaps[CASE_NUM]     ;
    integer                              case_win_bad[CASE_NUM][9];//wrong positions per window index
    bit                                  case_finished[CASE_NUM] ;
    bit                                  test_complete           = 0;
    string                               case_name[CASE_NUM]     ;
    integer                              tb_case_id              = -1;
    logic         [8*40-1:0]             tb_case_name            = 0;
    logic         [31:0]                 random_state            = SEED;
    logic         [31:0]                 drive_state             = SEED ^ 32'h5a5a1234;
    integer                              ready_mode              = 1; // 1: ready, 2: reproducible random.
    logic                                checking                = 0;
    logic                                previous_stall          = 0;
    logic         [TAP*9*PIX+UW-1:0]     previous_payload        = 0;
    logic                                previous_input_stall    = 0;
    logic         [DW+UW-1:0]            previous_input_payload  = 0;

    // Only the free-running clock generator uses time delays.
    always #(PIXEL_HALF) clk = ~clk;

    function automatic [31:0] next_random(input [31:0] value);
        logic         [31:0]             x ;
        begin
            x           = value ^ (value << 13);
            x           = x ^ (x >> 17);
            next_random = x ^ (x << 5);
        end
    endfunction
    // Source image: pixel value is a function of frame tag and position only.
    function automatic [PIX-1:0] pixel(input integer tag, line_id, column_id);
        logic         [31:0]             x ;
        begin
            x     = next_random(32'h9e3779b9 ^ (tag << 20) ^ (line_id << 10) ^ column_id);
            x     = next_random(x);
            pixel = PIX'(x >> 7);
        end
    endfunction
    function automatic [DW-1:0] payload(input integer tag, line_id, beat_id);
        logic         [DW-1:0]           result ;
        begin
            for (int lane = 0; lane < TAP; lane++)
                result[lane*PIX +: PIX] = pixel(tag, line_id, beat_id*TAP + lane);
            payload = result;
        end
    endfunction
    function automatic [DW-1:0] garbage(input [31:0] value);
        logic         [DW-1:0]           result ;
        logic         [31:0]             x      ;
        begin
            x = value;
            for (int lane = 0; lane < TAP; lane++) begin
                x                       = next_random(x);
                result[lane*PIX +: PIX] = PIX'(x >> 5);
            end
            garbage = result;
        end
    endfunction
    function automatic [UW-1:0] flags(input bit sof, sol, eol, eof);
        logic         [UW-1:0]           result ;
        begin
            result       = '0;
            result[`SOF] = sof;
            result[`SOL] = sol;
            result[`EOL] = eol;
            result[`EOF] = eof;
            flags        = result;
        end
    endfunction

    task automatic report_results;
        $display("========== SUMMARY TAP=%0d PIX=%0d UW=%0d LINE_BEATS=%0d HEIGHT=%0d SEED=%h ==========",
                 TAP, PIX, UW, LINE_BEATS, HEIGHT, SEED);
        for (int id = 0; id < CASE_NUM; id++) begin
            $display("%0d %-28s %s sent=%0d received=%0d gaps=%0d errors=%0d", id, case_name[id],
                     !case_finished[id] ? "INCOMPLETE" : case_errors[id]==0 ? "PASS" : "FAIL",
                     case_sent[id], case_received[id], case_gaps[id], case_errors[id]);
            if (case_finished[id] && case_errors[id] != 0)
                $display("    wrong positions per window index 0..8: %0d %0d %0d / %0d %0d %0d / %0d %0d %0d",
                         case_win_bad[id][0], case_win_bad[id][1], case_win_bad[id][2],
                         case_win_bad[id][3], case_win_bad[id][4], case_win_bad[id][5],
                         case_win_bad[id][6], case_win_bad[id][7], case_win_bad[id][8]);
        end
    endtask
    task automatic fail(input string message);
        errors++;
        if (errors - case_start_errors <= PRINT_LIMIT)
            $display("ERROR cycle=%0d case=%0d (%s): %s", cycles, tb_case_id,
                     tb_case_id < 0 ? "none" : case_name[tb_case_id], message);
        else if (errors - case_start_errors == PRINT_LIMIT + 1)
            $display("ERROR cycle=%0d case=%0d: more errors in this case, counted but not printed", cycles, tb_case_id);
        if (errors >= ERROR_LIMIT) begin
            report_results();
            $display("TEST FAILED: error limit reached");
            $fatal(1, "error limit");
        end
    endtask

    always @ (posedge clk) begin : monitor
        expected_t item;
        integer                          bad , first_lane, first_win;
        cycles++;
        random_state <= next_random(random_state);
        m_ready      <= ready_mode == 1 ? 1'b1 : random_state[1:0] != 0;
        if (cycles > 400000) begin
            report_results();
            $display("TEST FAILED: global watchdog case=%0d", tb_case_id);
            $fatal(1, "global watchdog");
        end
        if (!rst_n || !checking) begin
            previous_stall       = 0;
            previous_input_stall = 0;
        end else begin
            if (previous_input_stall && (!s_valid || {s_user,s_data} !== previous_input_payload))
                fail("source driver changed an unaccepted beat");
            previous_input_stall   = s_valid && !s_ready;
            previous_input_payload = {s_user,s_data};
            if (previous_stall && (!m_valid || {m_user, m_data} !== previous_payload))
                fail("output payload/valid changed under backpressure");
            previous_stall   = m_valid && !m_ready;
            previous_payload = {m_user, m_data};
            if (s_valid && s_ready)
                sent++;
            if (m_valid && m_ready) begin
                received++;
                if (expected.size() == 0)
                    fail("unexpected output transaction");
                else begin
                    item = expected.pop_front();
                    // Compare every window position that lies inside the image.
                    bad = 0;
                    for (int lane = 0; lane < TAP; lane++)
                        for (int w = 0; w < 9; w++)
                            if (item.mask[lane][w] && m_data[lane][w] !== item.data[lane][w]) begin
                                if (bad == 0) begin
                                    first_lane = lane;
                                    first_win  = w;
                                end
                                bad++;
                                case_win_bad[tb_case_id][w]++;
                            end
                    if (bad != 0)
                        fail($sformatf("window frame=%0d line=%0d beat=%0d: %0d positions wrong, first lane=%0d win[%0d] got=%h expected=%h",
                                       item.frame_id, item.line_id, item.beat_id, bad, first_lane, first_win,
                                       m_data[first_lane][first_win], item.data[first_lane][first_win]));
                    if (m_user !== item.user_bits)
                        fail($sformatf("user frame=%0d line=%0d beat=%0d got=%h expected=%h",
                                       item.frame_id, item.line_id, item.beat_id, m_user, item.user_bits));
                end
                if (m_user[`EOF] && !m_user[`EOL])
                    fail("EOF without EOL");
                if (m_user[`SOF] && !m_user[`SOL])
                    fail("SOF without SOL");
            end
        end
    end

    // Main reset is pulsed once; the DUT has no enable, cases are separated by idle time.
    task automatic reset_dut;
        @(posedge clk);
        checking   <= 0;
        rst_n      <= 0;
        s_valid    <= 0;
        s_user     <= 0;
        ready_mode <= 1;
        repeat(8) @(posedge clk);
        expected.delete();
        rst_n <= 1;
        repeat(8) @(posedge clk);
        checking <= 1;
        @(posedge clk);
    endtask

    // One source clock: drive, then wait until the DUT took it (s_ready = pipeline enable).
    // Idle clocks are counted the same way, so blanking is measured in enabled clocks.
    task automatic drive_cycle(input logic valid_value,
                               input  logic  [DW-1:0]           data_value ,
                               input  logic  [UW-1:0]           user_value );
        integer                          count ;
        s_valid <= valid_value;
        s_data  <= data_value;
        s_user  <= user_value;
        count   =  0;
        do begin
            @(posedge clk);
            count++;
            if (count >= WAIT_LIMIT) begin
                fail("input handshake timeout");
                report_results();
                $display("TEST FAILED: input timeout");
                $fatal(1, "input timeout");
            end
        end while (!s_ready);
    endtask
    // tvalid low: tdata / tuser carry garbage, they are only valid in a handshake.
    task automatic idle_cycles(input integer count);
        repeat(count) begin
            drive_state = next_random(drive_state);
            drive_cycle(1'b0, garbage(drive_state), UW'(drive_state >> 11));
        end
    endtask

    task automatic send_frame(input integer tag, gap_mode, gap_beat);
        integer                          gap ;
        for (int y = 0; y < HEIGHT; y++) begin
            for (int b = 0; b < LINE_BEATS; b++) begin
                drive_state = next_random(drive_state);
                case (gap_mode)
                    GAP_ONE   : gap = (b == gap_beat) ? 1 : 0;
                    GAP_RANDOM: gap = drive_state[9] ? 0 : int'(drive_state[5:4]);
                    default   : gap = 0;
                endcase
                gaps += gap;
                idle_cycles(gap);
                drive_cycle(1'b1, payload(tag, y, b),
                            flags(y==0 && b==0, b==0, b==LINE_BEATS-1, y==HEIGHT-1 && b==LINE_BEATS-1));
            end
            idle_cycles(LINE_GAP);
        end
        idle_cycles(FRAME_GAP);
    endtask

    // Reference: built from the source image and the position only, not from DUT state or timing.
    // Output beat (line, beat) carries for every lane the 3x3 window centered on that pixel.
    task automatic expect_frame(input integer tag, frame_id);
        expected_t item;
        integer                          src_y , src_x;
        for (int y = 0; y < HEIGHT; y++)
            for (int b = 0; b < LINE_BEATS; b++) begin
                item = '0;
                for (int lane = 0; lane < TAP; lane++)
                    for (int w = 0; w < 9; w++) begin
                        src_y = y + w/3 - 1;
                        src_x = b*TAP + lane + w%3 - 1;
                        if (src_y >= 0 && src_y < HEIGHT && src_x >= 0 && src_x < WIDTH) begin
                            item.data[lane][w] = pixel(tag, src_y, src_x);
                            item.mask[lane][w] = 1'b1;
                        end
                    end
                item.user_bits = flags(y==0 && b==0, b==0, b==LINE_BEATS-1, y==HEIGHT-1 && b==LINE_BEATS-1);
                item.frame_id  = 16'(frame_id);
                item.line_id   = 16'(y);
                item.beat_id   = 16'(b);
                expected.push_back(item);
            end
    endtask

    // Missing output is a case failure, the next case still runs.
    task automatic drain;
        integer                          count ;
        count = 0;
        while ((expected.size() != 0 || m_valid) && count < WAIT_LIMIT) begin
            @(posedge clk);
            count++;
        end
        if (expected.size() != 0) begin
            fail($sformatf("drain timeout: %0d expected transactions remain", expected.size()));
            expected.delete();
        end
        repeat(FRAME_GAP) @(posedge clk);
    endtask

    task automatic run_frames(input integer ready_value, gap_mode, gap_beat);
        ready_mode <= ready_value;
        @(posedge clk);
        for (int f = 0; f < FRAME_NUM; f++) begin
            expect_frame(tb_case_id*16 + f, f);
            send_frame(tb_case_id*16 + f, gap_mode, gap_beat);
        end
    endtask

    task automatic run_case(input integer id);
        integer                          start_sent , start_received, start_gaps;
        @(posedge clk);
        tb_case_id        = id;
        tb_case_name      = 320'(case_name[id]);
        case_start_errors = errors;
        start_sent        = sent;
        start_received    = received;
        start_gaps        = gaps;
        $display("========== CASE %0d %s BEGIN ==========", id, case_name[id]);
        case (id)
            0: case_cont_valid_ready();
            1: case_cont_valid_random_ready();
            2: case_one_gap_mid_line();
            3: case_one_gap_before_last_beat();
            4: case_random_gap_ready();
            5: case_random_gap_random_ready();
            6: case_cont_valid_after_gap();
        endcase
        drain();
        @(posedge clk);
        case_errors[id]   = errors-case_start_errors;
        case_sent[id]     = sent-start_sent;
        case_received[id] = received-start_received;
        case_gaps[id]     = gaps-start_gaps;
        case_finished[id] = 1;
        $display("========== CASE %0d %s %s (%0d errors) ==========", id, case_name[id],
                 case_errors[id]==0 ? "PASS" : "FAIL", case_errors[id]);
    endtask

    initial begin
        @(posedge clk);
        case_name[0] = "cont_valid_ready";
        case_name[1] = "cont_valid_random_ready";
        case_name[2] = "one_gap_mid_line";
        case_name[3] = "one_gap_before_last_beat";
        case_name[4] = "random_gap_ready";
        case_name[5] = "random_gap_random_ready";
        case_name[6] = "cont_valid_after_gap";
        for (int id = 0; id < CASE_NUM; id++)
            for (int w = 0; w < 9; w++)
                case_win_bad[id][w] = 0;
        reset_dut();
        for (int id = 0; id < CASE_NUM; id++) run_case(id);
        @(posedge clk);
        report_results();
        if (errors != 0) begin
            $display("TEST FAILED");
            $fatal(1, "scoreboard errors=%0d", errors);
        end
        $display("TEST PASSED");
        test_complete = 1;
        $finish;
    end

    matrix_3x3_gen #(
        .PIXEL_WIDTH           (PIX       ),
        .PIXEL_TAP_NUM         (TAP       ),
        .PIXEL_AXIS_USER_WIDTH (UW        ),
        .PIXEL_LINE_WIDTH_MAX  (LINE_MAX  )
    ) dut (
        .i_pixel_clk           (clk       ),
        .i_pixel_rst_n         (rst_n     ),
        .i_x_width             (width_cfg ),
        .i_y_height            (height_cfg),
        .i_s_axis_tvalid       (s_valid   ),
        .o_s_axis_tready       (s_ready   ),
        .i_s_axis_tdata        (s_data    ),
        .i_s_axis_tuser        (s_user    ),
        .o_m_axis_tvalid       (m_valid   ),
        .i_m_axis_tready       (m_ready   ),
        .o_m_axis_tdata        (m_data    ),
        .o_m_axis_tuser        (m_user    )
    );

    // Baseline: tvalid continuous inside a line, the module must pass these.
    task automatic case_cont_valid_ready;
        run_frames(1, GAP_NONE, 0);
    endtask
    task automatic case_cont_valid_random_ready;
        run_frames(2, GAP_NONE, 0);
    endtask
    // Smallest reproduction: one idle clock in the middle of every line.
    task automatic case_one_gap_mid_line;
        run_frames(1, GAP_ONE, LINE_BEATS/2);
    endtask
    // One idle clock right before the last beat of every line.
    task automatic case_one_gap_before_last_beat;
        run_frames(1, GAP_ONE, LINE_BEATS-1);
    endtask
    // Stress: random tvalid gaps, without and with random backpressure.
    task automatic case_random_gap_ready;
        run_frames(1, GAP_RANDOM, 0);
    endtask
    task automatic case_random_gap_random_ready;
        run_frames(2, GAP_RANDOM, 0);
    endtask
    // Continuous tvalid again: shows whether the module recovers after gapped frames.
    task automatic case_cont_valid_after_gap;
        run_frames(1, GAP_NONE, 0);
    endtask

endmodule
