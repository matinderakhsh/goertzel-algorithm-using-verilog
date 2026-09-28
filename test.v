`timescale 1ns/1ps

module tb_goertzel_q15;

    parameter integer N_SAMPLES = 256;

    reg clk;
    reg rst_n;
    reg start;
    reg in_valid;
    reg signed [15:0] x_in;

    wire out_valid;
    wire signed [15:0] X_re;
    wire signed [15:0] X_im;

    function signed [15:0] clamp_q15;
        input integer v;
        begin
            if (v >  32767) v =  32767;
            if (v < -32768) v = -32768;
            clamp_q15 = v[15:0];
        end
    endfunction

    function signed [15:0] make_sine_q15;
        input integer n;
        input integer k_in;
        real PI;
        real x;
        integer qi;
        begin
            PI = 3.14159265358979323846;
            x  = 0.7 * $sin(2.0*PI*k_in*n/N_SAMPLES);
            qi = $rtoi(x * 32768.0);
            make_sine_q15 = clamp_q15(qi);
        end
    endfunction

    function real q15_to_real;
        input signed [15:0] q;
        begin
            q15_to_real = $itor(q) / 32768.0;
        end
    endfunction

    goertzel_q15 #(
        .N_SAMPLES  (N_SAMPLES),
        .COEFF_2COS (16'h7642), // k=16, N=256
        .COS_W      (16'h7642),
        .SIN_W      (16'h30FC)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .in_valid (in_valid),
        .x_in     (x_in),
        .out_valid(out_valid),
        .X_re     (X_re),
        .X_im     (X_im)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    integer n;

    task send_frame;
        input integer kfreq;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            for (n = 0; n < N_SAMPLES; n = n + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                x_in     = make_sine_q15(n, kfreq);
            end

            @(negedge clk);
            in_valid = 1'b0;
            x_in     = 16'sd0;
        end
    endtask

    task wait_outvalid;
        begin
            while (out_valid !== 1'b1) begin
                @(posedge clk);
            end
        end
    endtask

    integer k_in;

    initial begin
        rst_n    = 1'b0;
        start    = 1'b0;
        in_valid = 1'b0;
        x_in     = 16'sd0;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        k_in = 16;
        $display("=== Frame 1: input sine k=%0d ===", k_in);
        send_frame(k_in);
        wait_outvalid();

        repeat (5) @(negedge clk);

        k_in = 20;
        $display("=== Frame 2: input sine k=%0d ===", k_in);
        send_frame(k_in);
        wait_outvalid();

        repeat (20) @(negedge clk);
        $finish;
    end

    always @(posedge clk) begin
        if (out_valid) begin
            $display("t=%0t OUT_VALID  X_re=0x%0h X_im=0x%0h  X_re=%.6f X_im=%.6f",
                     $time, X_re, X_im, q15_to_real(X_re), q15_to_real(X_im));
        end
    end

endmodule