// Простая двухпортовая память для хранения интервалов
module simple_dpram #(
    parameter int ADDR_W = 6,
    parameter int DATA_W = 32
)(
    input  logic              clk,
    // Port A - Write
    input  logic [ADDR_W-1:0] w_addr,
    input  logic [DATA_W-1:0] w_data,
    input  logic              w_en,
    // Port B - Read
    input  logic [ADDR_W-1:0] r_addr,
    output logic [DATA_W-1:0] r_data
);
    // Никаких инициализаций и сбросов массива!
    logic [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    always_ff @(posedge clk) begin
        if (w_en) mem[w_addr] <= w_data;
    end

    // Регистровое чтение для стабильных таймингов
    always_ff @(posedge clk) begin
        r_data <= mem[r_addr];
    end
endmodule