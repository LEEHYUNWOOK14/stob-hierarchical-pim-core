module fp32_mul (
    input  logic [31:0] lhs_i,
    input  logic [31:0] rhs_i,
    output logic [31:0] result_o
);
    logic sign, round_up;
    logic [7:0] lhs_exp, rhs_exp, result_exp_field;
    logic [22:0] lhs_frac, rhs_frac;
    logic [23:0] lhs_sig, rhs_sig;
    logic [47:0] product;
    logic [127:0] magnitude, rounded_wide, low_mask;
    integer lhs_unbiased, rhs_unbiased, exponent, msb_index, shift_amount;

    always @* begin
        sign = lhs_i[31] ^ rhs_i[31];
        lhs_exp = lhs_i[30:23]; rhs_exp = rhs_i[30:23];
        lhs_frac = lhs_i[22:0]; rhs_frac = rhs_i[22:0];
        lhs_sig = {lhs_exp != 0, lhs_frac};
        rhs_sig = {rhs_exp != 0, rhs_frac};
        product = lhs_sig * rhs_sig;
        magnitude = product;
        lhs_unbiased = lhs_exp == 0 ? -126 : lhs_exp - 127;
        rhs_unbiased = rhs_exp == 0 ? -126 : rhs_exp - 127;
        msb_index = 0;
        for (integer bit_index = 0; bit_index < 48; bit_index = bit_index + 1)
            if (product[bit_index]) msb_index = bit_index;
        exponent = lhs_unbiased + rhs_unbiased - 46 + msb_index;
        rounded_wide = '0; low_mask = '0; round_up = 0;
        result_exp_field = '0; shift_amount = 0;
        if ((lhs_exp == 8'hff && lhs_frac != 0) ||
            (rhs_exp == 8'hff && rhs_frac != 0) ||
            ((lhs_exp == 8'hff || rhs_exp == 8'hff) &&
             ((lhs_exp == 0 && lhs_frac == 0) || (rhs_exp == 0 && rhs_frac == 0))))
            result_o = 32'h7fc00000;
        else if (lhs_exp == 8'hff || rhs_exp == 8'hff)
            result_o = {sign, 8'hff, 23'b0};
        else if ((lhs_exp == 0 && lhs_frac == 0) || (rhs_exp == 0 && rhs_frac == 0))
            result_o = {sign, 31'b0};
        else if (exponent >= 128) result_o = {sign, 8'hff, 23'b0};
        else if (exponent >= -126) begin
            shift_amount = msb_index - 23;
            if (shift_amount > 0) begin
                rounded_wide = magnitude >> shift_amount;
                low_mask = (128'd1 << (shift_amount-1)) - 1'b1;
                round_up = magnitude[shift_amount-1] &&
                           ((|(magnitude & low_mask)) || rounded_wide[0]);
                rounded_wide = rounded_wide + round_up;
            end else rounded_wide = magnitude << (-shift_amount);
            if (rounded_wide >= (128'd1 << 24)) begin
                rounded_wide = rounded_wide >> 1;
                exponent = exponent + 1;
            end
            if (exponent >= 128) result_o = {sign, 8'hff, 23'b0};
            else begin
                result_exp_field = exponent + 127;
                result_o = {sign, result_exp_field, rounded_wide[22:0]};
            end
        end else begin
            shift_amount = -(lhs_unbiased + rhs_unbiased + 103);
            if (shift_amount >= 128) rounded_wide = 0;
            else if (shift_amount > 0) begin
                rounded_wide = magnitude >> shift_amount;
                low_mask = (128'd1 << (shift_amount-1)) - 1'b1;
                round_up = magnitude[shift_amount-1] &&
                           ((|(magnitude & low_mask)) || rounded_wide[0]);
                rounded_wide = rounded_wide + round_up;
            end else rounded_wide = magnitude << (-shift_amount);
            if (rounded_wide >= (128'd1 << 23)) result_o = {sign, 8'd1, 23'd0};
            else result_o = {sign, 8'd0, rounded_wide[22:0]};
        end
    end
endmodule
