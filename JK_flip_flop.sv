module jk_flip_flop(
    input logic clk,
    input logic rst_n,
    input logic j,
    input logic k,
    output logic q,
    output logic q_n
);

assign q_n = ~q;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        q <= 1'b0;
    end else begin 
        case({j,k})
            2'b00: q <= q;
            2'b01: q <= 1'b0;
            2'b10: q <= 1'b1;
            2'b11: q <= ~q;
            default: q<= 1'bx;
        endcase
    end
end

endmodule


module d_flip_flop(
    input logic clk,
    input logic rst_n,
    input logic D,
    output logic Q,
    output logic Q_n
);

always_ff @(posedge clk, jr negedge rst_n) begin
    if(!rst_n) begin
        Q <= 1'b0;
        Q_n <= 1'b1;
    end else begin
        Q <= D;
        Q_n <= ~D;
    end
end

endmodule