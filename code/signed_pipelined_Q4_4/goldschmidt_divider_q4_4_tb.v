module goldschmidt_divider_q4_4_tb;

reg clk, rst_n, start;
reg signed [7:0] numerator, denominator;
wire signed [7:0] quotient;
wire valid, error;

// Clock generation
always #5 clk = ~clk;

goldschmidt_divider_q4_4 dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .numerator(numerator),
    .denominator(denominator),
    .quotient(quotient),
    .valid(valid),
    .error(error)
);

initial begin
    clk = 0;
    rst_n = 0;
    start = 0;
    numerator = 0;
    denominator = 0;
  
    #20 rst_n = 1;


    // 2.0 / 1.0 = 2.0 → 0x20
    #10; numerator = 8'h20; denominator = 8'h10; start = 1; #10 start = 0;
    wait(valid);
    $display("Unsigned Test 1: 2.0 / 1.0 = %h (Expected: 20)", quotient);

    // 1.0 / 2.0 = 0.5 → 0x08
    #20; numerator = 8'h10; denominator = 8'h20; start = 1; #10 start = 0;
    wait(valid);
    $display("Unsigned Test 2: 1.0 / 2.0 = %h (Expected: 08)", quotient);

    // 2.0 / 2.0 = 1.0 → 0x10
    #20; numerator = 8'h20; denominator = 8'h20; start = 1; #10 start = 0;
    wait(valid);
    $display("Unsigned Test 3: 2.0 / 2.0 = %h (Expected: 10)", quotient);

    // 2.0 / 0.0 = error
    #20; numerator = 8'h20; denominator = 8'h00; start = 1; #10 start = 0;
    wait(valid);
    if (error)
        $display("Unsigned Test 4: ERROR - Division by zero");
    else
        $display("Unsigned Test 4: 2.0 / 0.0 = %h (Expected: error)", quotient);

    // 2.0 / 7.0 ≈ 0.2857 → ~0x05
    #20; numerator = 8'h20; denominator = 8'h70; start = 1; #10 start = 0;
    wait(valid);
    $display("Unsigned Test 5: 2.0 / 7.0 = %h (Expected: ~05)", quotient);

    // 2.75 / 1.25 ≈ 2.2 → ~0x23
    #20; numerator = 8'h2C; denominator = 8'h14; start = 1; #10 start = 0;
    wait(valid);
    $display("Unsigned Test 6: 2.75 / 1.25 = %h (Expected: ~23)", quotient);


    // -8 / 2 = -4 → -4.0 = 0xC0
    #20; numerator = -8'sd8 << 4; denominator = 8'sd2 << 4; start = 1; #10 start = 0;
    wait(valid);
    $display("Signed Test 1: -8 / 2 = %h (Expected: C0)", quotient);

    // -2 / -2 = 1 → 0x10
    #20; numerator = -8'sd2 << 4; denominator = -8'sd2 << 4; start = 1; #10 start = 0;
    wait(valid);
    $display("Signed Test 2: -2 / -2 = %h (Expected: 10)", quotient);

    // -1 / 2 = -0.5 → 0xF8
    #20; numerator = -8'sd1 << 4; denominator = 8'sd2 << 4; start = 1; #10 start = 0;
    wait(valid);
    $display("Signed Test 3: -1 / 2 = %h (Expected: F8)", quotient);

    // -1 / -2 = +0.5 → 0x08
    #20; numerator = -8'sd1 << 4; denominator = -8'sd2 << 4; start = 1; #10 start = 0;
    wait(valid);
    $display("Signed Test 4: -1 / -2 = %h (Expected: 08)", quotient);

    // 2 / -1 = -2.0 → 0xE0
    #20; numerator = 8'sd2 << 4; denominator = -8'sd1 << 4; start = 1; #10 start = 0;
    wait(valid);
    $display("Signed Test 5: 2 / -1 = %h (Expected: E0)", quotient);

    #100 $finish;
end

endmodule
