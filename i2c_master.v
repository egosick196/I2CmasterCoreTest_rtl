`timescale 1ns/1ps
module i2c_master(
                        sys_clk,  // ϵͳʱ��Ƶ�ʸ��ģ�50MHz
                        rst_n,
                        scl,
                        sda
                        //at24c02_00_data
                        );
                                            
    input			sys_clk;
    input			rst_n;  // ��λ�źţ��͵�ƽ��Ч
    output			scl;			//I2Cʱ������
    inout			sda;			//I2C��������
    (*mark_debug = "true"*) /*output*/ wire	[7:0]	at24c02_00_data;
    
                            
    (*mark_debug = "true"*) wire clk_div_12M, clk_buffed_50M;
    wire clk_div_100k;	//�ɷ�Ƶmodule������ʱ���ź�

    clkAdapter clkAdapter_u1(
        .CLK_IN1(sys_clk),
        .RESET(1'b0),
        .CLK_OUT1(clk_div_12M),
        .CLK_OUT2(clk_buffed_50M),
        .LOCKED()
    );

    /* ������������ */
    reg key_in_ff0 = 0, key_in_ff1 = 0;
    reg [19:0] cnt = 0;
    wire add_cnt, end_cnt;
    (*mark_debug = "true"*) wire resetSW;
    reg flag;

	assign resetSW = !flag;  // resetSWΪ�͵�ƽ��Ч

    always @(posedge clk_buffed_50M) begin
        key_in_ff0 <= rst_n;
        key_in_ff1 <= key_in_ff0;
    end

    // ��ʱ10ms��������������ʱ������0.02us��
    always @(posedge clk_buffed_50M) begin
        if(add_cnt) begin
            if(end_cnt)
                cnt <= 20'b0;
            else
                cnt <= cnt + 1'b1;
        end
        else
            cnt <= 0;
    end

    assign add_cnt = (flag == 1'b0) && (key_in_ff1 == 0);
    assign end_cnt = add_cnt && (cnt == 500_000 - 1);

    always @(posedge clk_buffed_50M) begin
        if(end_cnt) begin
            flag <= 1'b1;
        end
        else if (key_in_ff1 == 0) begin
            flag <= 1'b0;
        end
    end

    clk_div clk_div_inst(			//��Ƶ��
        .clk(clk_div_12M),				
        .rst_n(resetSW),   
        .clkout(clk_div_100k)
        );
            
    wire	[7:0]	i2c_read_data;	//I2C��ȡ����
    wire	[7:0]	i2c_reg_data;	//I2Cд��Ĵ�������
    wire	[7:0]	i2c_reg_addr;	//I2Cд��Ĵ�����ַ
    wire	[6:0]	i2c_dev_addr;	//�ӻ��豸��ַ
    (*mark_debug = "true"*) wire	[7:0]	i2c_config;		//I2Cģʽ�����ź�
    wire	[7:0]	i2c_ack;		//I2C��Ӧ�ź�
    wire	[7:0]	state_debug;	//״ָ̬ʾ�ź�

    i2c_master_config i2c_master_config_inst(
        .clk_12m(clk_div_12M),
        .rst_n(resetSW),
        .scl(scl),
        .sda(sda),
        .i2c_clk(clk_div_100k),
        .i2c_dev_addr(i2c_dev_addr),
        .i2c_reg_addr(i2c_reg_addr),
        .i2c_reg_data(i2c_reg_data),
        .i2c_read_data(i2c_read_data),
        .i2c_config(i2c_config),
        .i2c_ack(i2c_ack),
        .state_debug(state_debug),
        .at24c02_00_data(at24c02_00_data)
    );					
                        
endmodule						