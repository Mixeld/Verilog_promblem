module d_flip_flop(
    input logic clk,
    input logic rst_n,
    input logic D,
    output logic Q,
    output logic Q_n
);

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        Q <= 1'b0;
        Q_n <= 1'b1;
    end else begin
        Q <= D;
        Q_n <= ~D;
    end
end

endmodule
