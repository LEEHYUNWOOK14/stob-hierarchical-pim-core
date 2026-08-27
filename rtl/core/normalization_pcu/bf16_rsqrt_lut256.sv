module bf16_rsqrt_lut256 (
    input logic clk_i, input logic rst_ni,
    input logic input_valid_i, output logic input_ready_o,
    input logic [15:0] input_data_i,
    output logic output_valid_o, input logic output_ready_i,
    output logic [15:0] output_data_o
);
    function automatic [15:0] approximate_rsqrt(input logic [15:0] value);
        logic sign;
        logic [7:0] exponent;
        logic [6:0] fraction;
        logic [7:0] normalized_mantissa;
        logic [8:0] adjusted_mantissa;
        logic signed [9:0] unbiased_exponent, even_exponent;
        logic signed [10:0] output_exponent;
        logic [8:0] delta;
        logic [7:0] index;
        logic [15:0] lut_value;
        integer leading_one;
        begin
            sign=value[15]; exponent=value[14:7]; fraction=value[6:0];
            normalized_mantissa='0; adjusted_mantissa='0;
            unbiased_exponent='0; even_exponent='0; output_exponent='0;
            delta='0; index='0; lut_value=16'h3f80; leading_one=-1;
            if(sign) approximate_rsqrt=16'h7fc0;
            else if(exponent==8'hff)
                approximate_rsqrt=fraction==0?16'h0000:16'h7fc0;
            else if(exponent==0&&fraction==0) approximate_rsqrt=16'h7f80;
            else begin
                if(exponent!=0) begin
                    normalized_mantissa={1'b1,fraction};
                    unbiased_exponent=$signed({1'b0,exponent})-10'sd127;
                end else begin
                    for(integer bit_index=6;bit_index>=0;bit_index=bit_index-1)
                        if(leading_one<0&&fraction[bit_index])leading_one=bit_index;
                    normalized_mantissa=fraction<<(7-leading_one);
                    unbiased_exponent=leading_one-133;
                end
                if(unbiased_exponent[0]) begin
                    adjusted_mantissa={normalized_mantissa,1'b0};
                    even_exponent=unbiased_exponent-1;
                end else begin
                    adjusted_mantissa=normalized_mantissa;
                    even_exponent=unbiased_exponent;
                end
                delta=adjusted_mantissa-9'd128;
                index=(delta*2)/3;
`include "rtl/bf16_rsqrt_lut256_case.svh"
                output_exponent=$signed({1'b0,lut_value[14:7]})-(even_exponent>>>1);
                approximate_rsqrt={1'b0,output_exponent[7:0],lut_value[6:0]};
            end
        end
    endfunction

    assign input_ready_o=!output_valid_o||output_ready_i;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin output_valid_o<=0;output_data_o<='0;end
        else if(input_ready_o) begin
            output_valid_o<=input_valid_i;
            if(input_valid_i)output_data_o<=approximate_rsqrt(input_data_i);
        end
    end
endmodule
