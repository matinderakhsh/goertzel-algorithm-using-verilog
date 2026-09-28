`timescale 1ns/1ps

module goertzel_q15 #(
    parameter integer N_SAMPLES = 256,
    parameter signed [15:0] COEFF_2COS = 16'h7FFF,
    parameter signed [15:0] COS_W      = 16'h7FFF,
    parameter signed [15:0] SIN_W      = 16'h0000
)(
    input               clk,
    input               rst_n,
    input               start,
    input               in_valid,
    input  signed [15:0] x_in,
    output reg          out_valid,
    output reg signed [15:0] X_re,
    output reg signed [15:0] X_im
);

    reg active;
    reg [31:0] count;

    reg signed [31:0] v1;
    reg signed [31:0] v2;

    reg signed [31:0] x32;
    reg signed [31:0] fb;
    reg signed [31:0] v0;

    reg signed [31:0] cosv2;
    reg signed [31:0] sinv2;
    reg signed [31:0] Xre32;
    reg signed [31:0] Xim32;

    function signed [31:0] mul_q214_q115_to_q115;
        input signed [15:0] a_q214;
        input signed [31:0] b_q115;
        reg   signed [47:0] p;
        begin
            p = $signed(a_q214) * $signed(b_q115);
            mul_q214_q115_to_q115 = $signed(p >>> 14);
        end
    endfunction

    function signed [31:0] mul_q115_q115_to_q115;
        input signed [15:0] a_q115;
        input signed [31:0] b_q115;
        reg   signed [47:0] p;
        begin
            p = $signed(a_q115) * $signed(b_q115);
            mul_q115_q115_to_q115 = $signed(p >>> 15);
        end
    endfunction

    function signed [15:0] trunc16;
        input signed [31:0] v;
        begin
            trunc16 = v[15:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            active    <= 1'b0;
            count     <= 32'd0;
            v1        <= 32'sd0;
            v2        <= 32'sd0;
            out_valid <= 1'b0;
            X_re      <= 16'sd0;
            X_im      <= 16'sd0;

            x32       <= 32'sd0;
            fb        <= 32'sd0;
            v0        <= 32'sd0;
            cosv2     <= 32'sd0;
            sinv2     <= 32'sd0;
            Xre32     <= 32'sd0;
            Xim32     <= 32'sd0;
        end else begin
            out_valid <= 1'b0;

            if (start) begin
                active <= 1'b1;
                count  <= 32'd0;
                v1     <= 32'sd0;
                v2     <= 32'sd0;
            end

            if (active && in_valid) begin
                x32 = {{16{x_in[15]}}, x_in};
                fb  = mul_q214_q115_to_q115(COEFF_2COS, v1);
                v0  = x32 + fb - v2;

                if (count == (N_SAMPLES-1)) begin
                    cosv2 = mul_q115_q115_to_q115(COS_W, v1);
                    sinv2 = mul_q115_q115_to_q115(SIN_W, v1);

                    Xre32 = v0 - cosv2;
                    Xim32 = sinv2;

                    X_re <= trunc16(Xre32);
                    X_im <= trunc16(Xim32);

                    out_valid <= 1'b1;
                    active    <= 1'b0;

                    v2 <= v1;
                    v1 <= v0;
                end else begin
                    v2 <= v1;
                    v1 <= v0;
                    count <= count + 1;
                end
            end
        end
    end

endmodule