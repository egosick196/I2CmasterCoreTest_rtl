`timescale 1ns/1ps
module i2c_master(
						sys_clk,  // 系统时钟频率更改：50MHz
						rst_n,
						scl,
						sda,
						at24c02_00_data
						);
											
	input			sys_clk;
	(*mark_debug = "true"*) input			rst_n;  // 复位信号，低电平有效
	output			scl;			//I2C时钟总线
	inout			sda;			//I2C数据总线
	(*mark_debug = "true"*) output	[7:0]	at24c02_00_data;
	
							
	(*mark_debug = "true"*) wire	clk_div_12M, clk_div_100k;			//由分频module产生的时钟信号

	clkAdapter clkAdapter_u1(
		.CLK_IN1(sys_clk),
		.RESET(!rst_n),
		.CLK_OUT1(clk_div_12M),
		.CLK_OUT2(clk_buffed_50M),
		.LOCKED()
	);

	clk_div clk_div_inst(			//分频器
		.clk(clk_div_12M),				
		.rst_n(rst_n),   
		.clkout(clk_div_100k)
		);
			
	wire	[7:0]	i2c_read_data;	//I2C读取数据
	wire	[7:0]	i2c_reg_data;	//I2C写入寄存器数据
	wire	[7:0]	i2c_reg_addr;	//I2C写入寄存器地址
	wire	[6:0]	i2c_dev_addr;	//从机设备地址
	wire	[7:0]	i2c_config;		//I2C模式配置信号
	wire	[7:0]	i2c_ack;		//I2C响应信号
	wire	[7:0]	state_debug;	//状态指示信号

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