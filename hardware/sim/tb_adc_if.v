`timescale 1ns/1ps

module tb_adc_if;

    localparam CLK_PERIOD = 16;

    reg         CLK_ADC = 0;
    reg  [11:0] ADC     = 12'h0;
    reg         OTR     = 0;
    wire [15:0] m_axis_tdata;
    wire        m_axis_tvalid;
    wire        m_axis_totr;
    reg         m_axis_tready = 1;

    always #(CLK_PERIOD/2) CLK_ADC = ~CLK_ADC;

    adc_if dut (
        .CLK_ADC       (CLK_ADC),
        .ADC           (ADC),
        .OTR           (OTR),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_totr   (m_axis_totr),
        .m_axis_tready (m_axis_tready)
    );

    task apply_sample;
        input [11:0] data;
        input        otr;
        begin
            @(negedge CLK_ADC);
            ADC = data;
            OTR = otr;
        end
    endtask

    task check_output;
        input [15:0] exp_tdata;
        input        exp_otr;
        begin
            @(posedge CLK_ADC); #1;
            if (m_axis_tdata !== exp_tdata)
                $display("FAIL tdata: got %h, exp %h", m_axis_tdata, exp_tdata);
            if (m_axis_totr !== exp_otr)
                $display("FAIL totr: got %b, exp %b", m_axis_totr, exp_otr);
            if (!m_axis_tvalid)
                $display("FAIL: tvalid=0");
        end
    endtask

    integer i;
    initial begin
        $dumpfile("tb_adc_if.vcd");
        $dumpvars(0, tb_adc_if);

        repeat(4) @(posedge CLK_ADC);

        apply_sample(12'h000, 0); check_output(16'h0000, 0);
        apply_sample(12'h7FF, 0); check_output(16'h07FF, 0);
        apply_sample(12'h800, 0); check_output(16'hF800, 0);
        apply_sample(12'hFFF, 0); check_output(16'hFFFF, 0);
        apply_sample(12'h7FF, 1); check_output(16'h07FF, 1);

        m_axis_tready = 0;
        apply_sample(12'h123, 0);
        @(posedge CLK_ADC); #1;
        if (!m_axis_tvalid) $display("FAIL: tvalid must stay 1 with tready=0");
        m_axis_tready = 1;

        for (i = 0; i < 4096; i = i + 1) begin
            @(negedge CLK_ADC); ADC = i[11:0]; OTR = 0;
            @(posedge CLK_ADC); #1;
            if (ADC[11] && (m_axis_tdata[15:12] !== 4'hF))
                $display("FAIL sign-ext neg: code=%h tdata=%h", ADC, m_axis_tdata);
            if (!ADC[11] && (m_axis_tdata[15:12] !== 4'h0))
                $display("FAIL sign-ext pos: code=%h tdata=%h", ADC, m_axis_tdata);
        end

        $display("SIM DONE");
        $finish;
    end

endmodule
