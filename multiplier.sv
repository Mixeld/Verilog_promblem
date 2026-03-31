module multiplier #(
    parameter WIDTH = 8,
    parameter CONST = 10
)(
    input     logic [WIDTH - 1:0]     data_in,
    output    logic [WIDTH * 2 - 1:0] data_out
);

    localparam MAX_SHIFT = $clog2(CONST) + 1;

    logic [WIDTH * 2 - 1:0] sum;

    generate
        genvar i;

        logic [WIDTH * 2 - 1:0] shifted [0: MAX_SHIFT - 1];

        //Возможные сдвиги
        for (i = 0; i < MAX_SHIFT; i++) begin: gen_shifts
        // создать "пустое число из 0" -> передать значение data_in -> сдвинуть на i-ую 
            assign shifted[i]={{WIDTH{1'b0}}, data_in} << i; 

        end        

        always_comb begin 
            sum = 0;
            for (i = 0; i < MAX_SHIFT; i++) begin 
                if (CONST[i]) begin
                    sum = sum + shifted[i];
                end
            end
        end
        
        assign data_out = sum;

    endgenerate

endmodule