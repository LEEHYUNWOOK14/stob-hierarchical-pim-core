module fp32_add (
    input  logic [31:0] lhs_i,
    input  logic [31:0] rhs_i,
    output logic [31:0] result_o
);
    function automatic [26:0] shift_right_sticky(input logic [26:0] value,
                                                  input integer amount);
        logic sticky;
        begin
            if (amount <= 0) shift_right_sticky = value;
            else if (amount >= 27) shift_right_sticky = {26'b0, |value};
            else begin
                sticky = |(value & ((27'b1 << amount) - 1'b1));
                shift_right_sticky = value >> amount;
                shift_right_sticky[0] = shift_right_sticky[0] | sticky;
            end
        end
    endfunction

    logic lhs_sign, rhs_sign, large_sign, small_sign, result_sign, round_up;
    logic [7:0] lhs_exp, rhs_exp, large_exp, small_exp;
    logic [22:0] lhs_frac, rhs_frac;
    logic [23:0] lhs_sig, rhs_sig, large_sig, small_sig;
    logic [26:0] large_ext, small_ext, magnitude_ext;
    logic [27:0] add_ext;
    logic [24:0] rounded_sig;
    integer result_exp, shift_amount, normalize_step;

    always @* begin
        lhs_sign = lhs_i[31]; rhs_sign = rhs_i[31];
        lhs_exp = lhs_i[30:23]; rhs_exp = rhs_i[30:23];
        lhs_frac = lhs_i[22:0]; rhs_frac = rhs_i[22:0];
        lhs_sig = {lhs_exp != 0, lhs_frac};
        rhs_sig = {rhs_exp != 0, rhs_frac};
        large_sign = lhs_sign; small_sign = rhs_sign;
        large_exp = lhs_exp == 0 ? 8'd1 : lhs_exp;
        small_exp = rhs_exp == 0 ? 8'd1 : rhs_exp;
        large_sig = lhs_sig; small_sig = rhs_sig;
        if ({rhs_exp == 0 ? 8'd1 : rhs_exp, rhs_sig} >
            {lhs_exp == 0 ? 8'd1 : lhs_exp, lhs_sig}) begin
            large_sign = rhs_sign; small_sign = lhs_sign;
            large_exp = rhs_exp == 0 ? 8'd1 : rhs_exp;
            small_exp = lhs_exp == 0 ? 8'd1 : lhs_exp;
            large_sig = rhs_sig; small_sig = lhs_sig;
        end
        large_ext = {large_sig, 3'b000};
        shift_amount = large_exp - small_exp;
        small_ext = shift_right_sticky({small_sig, 3'b000}, shift_amount);
        result_sign = large_sign; result_exp = large_exp;
        normalize_step = 0; add_ext = '0;
        if (large_sign == small_sign) begin
            add_ext = {1'b0, large_ext} + {1'b0, small_ext};
            if (add_ext[27]) begin
                magnitude_ext = add_ext[27:1];
                magnitude_ext[0] = magnitude_ext[0] | add_ext[0];
                result_exp = result_exp + 1;
            end else magnitude_ext = add_ext[26:0];
        end else begin
            magnitude_ext = large_ext - small_ext;
            for (normalize_step = 0; normalize_step < 26; normalize_step = normalize_step + 1)
                if (!magnitude_ext[26] && result_exp > 1) begin
                    magnitude_ext = magnitude_ext << 1;
                    result_exp = result_exp - 1;
                end
        end
        round_up = magnitude_ext[2] &&
                   (magnitude_ext[1] || magnitude_ext[0] || magnitude_ext[3]);
        rounded_sig = {1'b0, magnitude_ext[26:3]} + round_up;
        if (rounded_sig[24]) begin
            rounded_sig = rounded_sig >> 1;
            result_exp = result_exp + 1;
        end
        result_o = {result_sign, result_exp[7:0], rounded_sig[22:0]};
        if ((lhs_exp == 8'hff && lhs_frac != 0) ||
            (rhs_exp == 8'hff && rhs_frac != 0) ||
            (lhs_exp == 8'hff && rhs_exp == 8'hff && lhs_sign != rhs_sign))
            result_o = 32'h7fc00000;
        else if (lhs_exp == 8'hff) result_o = {lhs_sign, 8'hff, 23'b0};
        else if (rhs_exp == 8'hff) result_o = {rhs_sign, 8'hff, 23'b0};
        else if ((lhs_exp == 0 && lhs_frac == 0) &&
                 (rhs_exp == 0 && rhs_frac == 0))
            result_o = {lhs_sign & rhs_sign, 31'b0};
        else if (magnitude_ext == 0) result_o = 32'h00000000;
        else if (result_exp >= 255) result_o = {result_sign, 8'hff, 23'b0};
        else if (result_exp <= 1 && !rounded_sig[23])
            result_o = {result_sign, 8'b0, rounded_sig[22:0]};
    end
endmodule

