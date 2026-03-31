module agc #(
    parameter INPUT_WIDTH   = 16,
    parameter OUTPUT_WIDTH  = 8,
    parameter GAIN_WIDTH    = 8,


    parameter COEF_F        = 4'd2,        // коэфициент 1/2
    parameter COEF_M        = 4'd4,        // коэфициент 1/4
    parameter COEF_S        = 4'd8         // коэфициент 1/8
) (
    input   logic                              clk,
    input   logic                              rst_n,
    input   logic signed  [INPUT_WIDTH  - 1:0] data_in ,
    output  logic signed  [OUTPUT_WIDTH - 1:0] data_out,
    output  logic         [GAIN_WIDTH   - 1:0] gain
);

    typedef logic signed  [INPUT_WIDTH  - 1:0] data16_t; 
    typedef logic signed  [OUTPUT_WIDTH - 1:0] data8_t;
    typedef logic         [GAIN_WIDTH   - 1:0] gain_t;
    typedef logic signed  [INPUT_WIDTH + GAIN_WIDTH - 1:0] product_t; 

    localparam TARGET_16BIT = 16'h2000;  // Уровень на котором АРУ должен будет работать в 16-бит сетке
    localparam TARGET_8BIT = 8'h40;
    
    data16_t amplitude;           // детектированная амплитуда
    data16_t error;               // ошибка (разница с целевым уровнем)
    gain_t   gain_reg;            // текущий коэффициент усиления
    gain_t   gain_adj;            // приращение усиления
    data16_t target_level;        // целевой уровень

    
    //Детектор амплитуды

    data16_t abs_value;            //модуль входного сигнала
    data16_t envelope;             //Пиковые значения (с учётом того что оно может затухать)

    always_comb begin
        if (data_in[INPUT_WIDTH-1])
            abs_value = -data_in; //инверсия для ситуации если сигнал будет отрицательным
        else 
            abs_value = data_in;
    end


    always_ff @(posedge clk or negedge rst_n) begin 
        if(!rst_n) begin
            envelope <= '0; 
        end else begin
            if (abs_value > envelope)
                envelope <= abs_value;
            else
                envelope <= envelope - (envelope >> 1);
        end
    end

    assign error = target_level - envelope;

    //регулятор усиления на коэффициенты 

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            gain_reg <= 8'h80;      //выставляем нулевое усиление 
            target_level <= TARGET_16BIT;
        end else begin              //АНАЛИЗИРУЕМ ПРИРАЩЕНИЕ В ЗАВИСИМОСТИ ОТ ОШИБКИ


            //ТИХО

            if(error > (TARGET_16BIT >> 2)) begin               
                gain_adj = error[GAIN_WIDTH - 1:0] >> 1;
            end
            else if (error > (TARGET_16BIT >> 3)) begin
                gain_adj = error[GAIN_WIDTH - 1:0] >> 2;        
            end
            else if (error > (TARGET_16BIT >> 4)) begin
                gain_adj = error[GAIN_WIDTH - 1:0] >> 3;
            end

            //ГРОМКО
            else if (error > 0) begin
                gain_adj = error[GAIN_WIDTH - 1:0] >> 3;
            end
            else if (error < -(TARGET_16BIT >> 3)) begin
                gain_adj = (-error[GAIN_WIDTH - 1:0]) >> 1; 
            end
            else if (error < 0) begin
                gain_adj = (-error[GAIN_WIDTH - 1:0]) >> 2;
            end else begin
                gain_adj = 0;
            end

            //ОБНОВЛЯЕМ УСИЛЕНИЕ 

            if(error > 0) begin
                if (gain_adj + gain_reg > 8'hFF)        //пытаемсяне допустить переполнения
                gain_reg <= 8'hFF;
                else 
                gain_reg <= gain_reg + gain_adj;
            end
            else if (error < 0) begin
                if(gain_reg > gain_adj)
                    gain_reg <= gain_reg - gain_adj;
                else 
                    gain_reg <= 8'h00;
            end
        end
    end

    //Умножение на коэфициент усиления 
    
    product_t product;
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            product <= '0;
        end else begin
            product <= data_in * gain_reg;
        end
    end


    //Преобразование 16 -> 8 (анализируем "9" бит. Если 1 = +1, 0 = +0)
    always_ff @(posedge clk) begin
        if(data_in[INPUT_WIDTH - 9])
            data_out <= data_in[15:8] + 1'b1;
        else
            data_out <= data_in[15:8]; 
    end


endmodule
