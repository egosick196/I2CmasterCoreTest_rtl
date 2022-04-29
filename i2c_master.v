`timescale 1ns/1ps
module i2c_master(
						sys_clk,  // ϵͳʱ��Ƶ�ʸ��ģ�50MHz
						rst_n,
						scl,
						sda,
						at24c02_00_data
						);
											
	input			sys_clk;
	input			rst_n;			//��λ�źţ��͵�ƽ��Ч
	output			scl;			//I2Cʱ������
	inout			sda;			//I2C��������
	output	[7:0]	at24c02_00_data;
	
							
	wire	clk_div_12M, clk_div_100k;			//�ɷ�Ƶmodule������ʱ���ź�

	clkAdapter clkAdapter_u1(
		.CLK_IN1(sys_clk),
		.RESET(!rst_n),
		.CLK_OUT1(clk_div_12M),
		.CLK_OUT2(clk_buffed_50M),
		.LOCKED()
	);

	clk_div clk_div_inst(			//��Ƶ��
		.clk(clk_div_12M),				
		.rst_n(rst_n),   
		.clkout(clk_div_100k)
		);
			
	wire	[7:0]	i2c_read_data;	//I2C��ȡ����
	wire	[7:0]	i2c_reg_data;	//I2Cд��Ĵ�������
	wire	[7:0]	i2c_reg_addr;	//I2Cд��Ĵ�����ַ
	wire	[6:0]	i2c_dev_addr;	//�ӻ��豸��ַ
	wire	[7:0]	i2c_config;		//I2Cģʽ�����ź�
	wire	[7:0]	i2c_ack;		//I2C��Ӧ�ź�
	wire	[7:0]	state_debug;	//״ָ̬ʾ�ź�
	
	i2c_master_config i2c_master_config_inst(
		.clk_12m(clk_div_12M),
		.rst_n(rst_n),
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