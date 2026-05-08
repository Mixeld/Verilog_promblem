module uart_tx #(
    parameter int CLK_FREQ = 100_000_000,
    parameter int BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] tx_byte,
    input  logic       tx_start,
    output logic       tx_busy,
    output logic       tx_done,
    output logic       tx_pin
);
    localparam int BIT_PERIOD = CLK_FREQ / BAUD_RATE;
    
    typedef enum {IDLE, START, DATA, STOP} state_t;
    state_t state;
    
    logic [31:0] clk_cnt;
    logic [2:0]  bit_idx;
    logic [7:0]  data;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx_pin <= 1'b1;
            tx_busy <= 1'b0;
            tx_done <= 1'b0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                IDLE: begin
                    tx_pin <= 1'b1;
                    if (tx_start) begin
                        data <= tx_byte;
                        state <= START;
                        tx_busy <= 1'b1;
                        clk_cnt <= 0;
                    end else tx_busy <= 1'b0;
                end
                START: begin
                    tx_pin <= 1'b0;
                    if (clk_cnt < BIT_PERIOD - 1) clk_cnt <= clk_cnt + 1;
                    else begin clk_cnt <= 0; state <= DATA; bit_idx <= 0; end
                end
                DATA: begin
                    tx_pin <= data[bit_idx];
                    if (clk_cnt < BIT_PERIOD - 1) clk_cnt <= clk_cnt + 1;
                    else begin
                        clk_cnt <= 0;
                        if (bit_idx < 7) bit_idx <= bit_idx + 1;
                        else state <= STOP;
                    end
                end
                STOP: begin
                    tx_pin <= 1'b1;
                    if (clk_cnt < BIT_PERIOD - 1) clk_cnt <= clk_cnt + 1;
                    else begin tx_done <= 1'b1; state <= IDLE; end
                end
            endcase
        end
    end
endmodule