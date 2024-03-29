module i2c_master_logic(
					clk_in,
					rst_n,
					scl,
					sda,
					i2c_device_address,
					i2c_reg_address,
					i2c_write_reg_data,
					i2c_read_data,
					state_debug,
					i2c_config,
					i2c_ack
					);

	input 			clk_in;				//输入时钟 = 100K or 400K
	input			rst_n;				//输入复位，低电平有效
	output			scl;				//I2C时钟信号
	inout			sda;				//I2C数据信号
	output	[7:0]	i2c_read_data;		//I2C读出数据
	input	[6:0]	i2c_device_address;	//I2C设备地址
	input	[7:0]	i2c_reg_address;	//I2C读/写目标寄存器地址
	input	[7:0]	i2c_write_reg_data;	//I2C写入数据
	(*mark_debug = "true"*) input	[7:0]	i2c_config;

	output	[7:0]	state_debug;	
	output	[7:0]	i2c_ack;
	
	/*
		i2c_ack[0] = 写入设备地址从机响应位
			   [1] = 写入寄存器地址从机响应位
			   [2] = 写入寄存器数据从机响应位	
			   [3] = 读取寄存器地址从机响应位
			   [4] = 读取寄存器数据主机发送ACK
			   [5] = 读取寄存器数据主机发送NACK
			   [6] = 0
			   [7] = 0
  	*/
	
	//I2C SCL
	(*mark_debug = "true"*) reg		scl_r 	= 1'b1;				
	assign	scl 	= scl_r;
	
	//I2C SDA IN/OUT控制
	(*mark_debug = "true"*) reg 	sda_ctl = 1'b0;
	(*mark_debug = "true"*) reg		sda_r 	= 1'b1;  
	assign 	sda = sda_ctl? sda_r : 1'bz;
	
	reg		[7:0]	i2c_read_data;		//I2C读取数据
	
	reg				write_done;			//写入完成信号
	reg				read_done;
	
	//I2C运行模式参数
	parameter		I2C_Wait					=	8'h00;
	parameter		I2C_Single_Write_Byte		= 	8'h01;
	parameter		I2C_Continuous_Write_Byte	=	8'h02;
	parameter		I2C_Write_Directly			=	8'h03;
	parameter		I2C_Single_Read_Byte		=	8'h04;
	parameter		I2C_Continuous_Read_Byte	=	8'h05;
	parameter		I2C_Read_Directly			=	8'h06;
	
	//状态机参数
	parameter		IDLE 			=	15'b000_0000_0000_0000;			//初始化状态
	
	parameter		START			=	15'b000_0000_0000_0001;			//I2C_START
	parameter		DEVICE_ADDR_W	=	15'b000_0000_0000_0010;			//设备地址+写
	parameter		W_ACK_DEV_ADDR	=	15'b000_0000_0000_0100;			//设备地址ACK
	parameter		DEVICE_REG_ADDR	= 	15'b000_0000_0000_1000;			//写入/读出寄存器目标地址
	parameter		W_ACK_REG_ADDR	=	15'b000_0000_0001_0000;			//寄存器地址ACK
	parameter		WRITE_REG_DATA	=	15'b000_0000_0010_0000;			//对目标寄存器地址写入数据
	parameter		W_ACK_WR_DATA	=	15'b000_0000_0100_0000;			//写入数据ACK
	
	parameter		START_R			=	15'b000_0000_1000_0000;			//读操作第二次起始状态
	parameter		DEVICE_ADDR_R	=	15'b000_0001_0000_0000;			//设备地址+读
	parameter		W_ACK_DEV_ADDR_R=	15'b000_0010_0000_0000;			//设备地址ACK
	parameter		READ_REG_DATA	= 	15'b000_0100_0000_0000;			//读取寄存器数据
	parameter		S_NO_ACK		=	15'b000_1000_0000_0000;    		//发送NACK
	parameter		S_ACK_RD_DATA	=	15'b001_0000_0000_0000;			//发送ACK
	parameter		STOP			=	15'b010_0000_0000_0000; 		//停止信号
	
	parameter		WAIT			=	15'b100_0000_0000_0000;
	
	(*mark_debug = "true"*) reg		[14:0]	state_current;		
	(*mark_debug = "true"*) reg		[14:0]	state_next;
	
	always@(posedge clk_in or negedge rst_n) begin 
		if(!rst_n) 
			state_current <= IDLE;
		else 
			state_current <= state_next;
	end
	
	reg	[2:0]	cnt_start;	
	reg	[3:0]	cnt_dev_addr;
	(*mark_debug = "true"*) reg	[2:0]	cnt_ack_addr;
	reg	[3:0]	cnt_reg_addr;
	reg	[2:0]	cnt_ack_r_addr;
	reg	[3:0]	cnt_write_reg_data;
	reg	[2:0]	cnt_ack_w_data;
	reg	[3:0]	cnt_read_reg_data;
	reg [2:0]	cnt_stop;
	reg	[2:0]	cnt_s_nack;
	reg	[2:0]	cnt_start_r;
	reg	[3:0]	cnt_dev_addr_r;
	reg	[2:0]	cnt_ack_addr_r;
	reg	[2:0]	cnt_s_ack;
	
	reg	[7:0]	i2c_ack;
	
	always@(*) begin 
		state_next = IDLE;
		if(i2c_config == WAIT) begin
			state_next <= WAIT; end	
		else if(i2c_config == I2C_Read_Directly) begin 
			case(state_current)	
				IDLE			:	begin 	state_next	=	START; 													end
				START			:	begin 	if(cnt_start == 2) 				state_next	=	DEVICE_ADDR_W;	
											else							state_next	=	START;					end							 			
				DEVICE_ADDR_W	:	begin 	if(cnt_dev_addr == 15)			state_next	=	W_ACK_DEV_ADDR;	
											else							state_next  = 	DEVICE_ADDR_W;			end	 					
				W_ACK_DEV_ADDR	:	begin 	if(cnt_ack_addr == 1) begin 
												if(sda == 1'b0)	begin		state_next 	= 	START_R;		end//若仿真可注释
																							
												else begin 					state_next  =	W_ACK_DEV_ADDR;		end		
																																
												end
											else if(sda == 1'b1) 			state_next	= 	IDLE; 
											else 							state_next	=	W_ACK_DEV_ADDR;			end																					
				START_R			:	begin	if(cnt_start_r == 3) 			state_next	=	DEVICE_ADDR_R;		
											else							state_next	=	START_R;				end	
				DEVICE_ADDR_R	:	begin	if(cnt_dev_addr_r == 15)		state_next	=	W_ACK_DEV_ADDR_R;	
											else							state_next  = 	DEVICE_ADDR_R;			end	 	
				W_ACK_DEV_ADDR_R:	begin 	if(cnt_ack_addr_r == 1) begin 
												if(sda == 1'b0)				state_next 	= 	READ_REG_DATA; 			//若仿真可注释掉本行											
												else if(sda == 1'b1) 		state_next	= 	W_ACK_DEV_ADDR_R; 		end
											else 							state_next	=	W_ACK_DEV_ADDR_R;		end				
				READ_REG_DATA	:	begin	if(cnt_read_reg_data == 15) 	state_next	=	S_NO_ACK;
											else 							state_next  = 	READ_REG_DATA;			end		
				S_NO_ACK		:	begin	if(cnt_s_nack == 1)  			state_next 	= 	STOP; 	
											else							state_next	= 	S_NO_ACK; end	
				STOP			:	begin 	if(cnt_stop == 5) 				state_next	=	IDLE;			
											else 							state_next	=	STOP;	end
				default			:	begin 	state_next	=	state_next;		end
			endcase
			end
		else if(i2c_config == I2C_Write_Directly) begin 
			case(state_current)	
				IDLE			:	begin 	state_next	=	START; 													end
				START			:	begin 	if(cnt_start == 2) 				state_next	=	DEVICE_ADDR_W;	
											else							state_next	=	START;					end							 			
				DEVICE_ADDR_W	:	begin 	if(cnt_dev_addr == 15)			state_next	=	W_ACK_DEV_ADDR;	
											else							state_next  = 	DEVICE_ADDR_W;			end	 					
				W_ACK_DEV_ADDR	:	begin 	if(cnt_ack_addr == 1) begin 
												if(sda == 1'b0)				state_next 	= 	WRITE_REG_DATA;		//若仿真可注释掉本行
												else						state_next  =	W_ACK_DEV_ADDR;			end
											else if(sda == 1'b1) 			state_next	= 	IDLE; 
											else 							state_next	=	W_ACK_DEV_ADDR;			end							
				WRITE_REG_DATA	:	begin 	if(cnt_write_reg_data == 15) 	state_next	=	W_ACK_WR_DATA;		
											else 							state_next  = 	WRITE_REG_DATA;			end	
				W_ACK_WR_DATA	:	begin 	if(cnt_ack_w_data == 1) begin 
												if(sda == 1'b0)				state_next 	= 	STOP; 					//若仿真可注释掉本行														
											else if(sda == 1'b1) 		state_next	= 	W_ACK_WR_DATA; 			end		
											else 							state_next	=	W_ACK_WR_DATA;			end																	
				STOP			:	begin 	if(cnt_stop == 5) 
													state_next	=	IDLE;	
											else 	state_next	=	STOP;	end
				default			:	begin 	state_next	=	state_next;		end  
			endcase 
			end
		else if(i2c_config == I2C_Continuous_Read_Byte) begin 
			case(state_current)	
				IDLE			:	begin 	state_next	=	START; 											end
				START			:	begin 	if(cnt_start == 2) 			state_next	=	DEVICE_ADDR_W;	
											else						state_next	=	START;				end							 			
				DEVICE_ADDR_W	:	begin 	if(cnt_dev_addr == 15)		state_next	=	W_ACK_DEV_ADDR;	
											else						state_next  = 	DEVICE_ADDR_W;		end	 					
				W_ACK_DEV_ADDR	:	begin 	if(cnt_ack_addr == 1) begin
												if(sda == 1'b0)			state_next 	= 	DEVICE_REG_ADDR; 	
												else					state_next  =	W_ACK_DEV_ADDR;		end
											else if(sda == 1'b1) 		state_next	= 	IDLE; 
											else 						state_next	=	W_ACK_DEV_ADDR;		end							
				DEVICE_REG_ADDR	:	begin 	if(cnt_reg_addr == 15)		state_next	=	W_ACK_REG_ADDR;	
											else 						state_next  = 	DEVICE_REG_ADDR;	end								
				W_ACK_REG_ADDR	:	begin 	if(cnt_ack_r_addr == 1) begin    
												if(sda == 1'b0)			state_next	=	START_R;				 																
												else if(sda == 1'b1) 	state_next	= 	W_ACK_REG_ADDR; 	end	
											else 						state_next	=	W_ACK_REG_ADDR;		end																	
				START_R			:	begin	if(cnt_start_r == 3) 		state_next	=	DEVICE_ADDR_R;		
											else						state_next	=	START_R;			end	
				DEVICE_ADDR_R	:	begin	if(cnt_dev_addr_r == 15)	state_next	=	W_ACK_DEV_ADDR_R;	
											else						state_next  = 	DEVICE_ADDR_R;		end	 	
				W_ACK_DEV_ADDR_R:	begin 	if(cnt_ack_addr_r == 1) begin 
												if(sda == 1'b0)			state_next 	= 	READ_REG_DATA; 					
												else if(sda == 1'b1) 	state_next	= 	W_ACK_DEV_ADDR_R; 	end		
											else 						state_next	=	W_ACK_DEV_ADDR_R;	end				
				READ_REG_DATA	:	begin	if(cnt_read_reg_data == 15) state_next	=	S_ACK_RD_DATA; 		
											else 						state_next  = 	READ_REG_DATA;		end							
				S_ACK_RD_DATA	:	begin 	if(cnt_s_ack == 1)			state_next	=	READ_REG_DATA;	
											else 						state_next  = 	S_ACK_RD_DATA;		end		
				default			:	begin 	state_next	=	state_next;		end
			endcase
			end
		else if(i2c_config == I2C_Continuous_Write_Byte) begin 
			case(state_current)	
				IDLE			:	begin 	state_next	=	START; 													end
				START			:	begin 	if(cnt_start == 2) 				state_next	=	DEVICE_ADDR_W;	
											else							state_next	=	START;					end							 			
				DEVICE_ADDR_W	:	begin 	if(cnt_dev_addr == 15)			state_next	=	W_ACK_DEV_ADDR;	
											else							state_next  = 	DEVICE_ADDR_W;			end	 					
				W_ACK_DEV_ADDR	:	begin 	if(cnt_ack_addr == 1) begin 
												if(sda == 1'b0)				state_next 	= 	DEVICE_REG_ADDR; 																	
												else						state_next  =	W_ACK_DEV_ADDR;			end
											else if(sda == 1'b1) 			state_next	= 	IDLE; 
											else 							state_next	=	W_ACK_DEV_ADDR;			end							
				DEVICE_REG_ADDR	:	begin 	if(cnt_reg_addr == 15)			state_next	=	W_ACK_REG_ADDR;	
											else 							state_next  = 	DEVICE_REG_ADDR;		end								
				W_ACK_REG_ADDR	:	begin 	if(cnt_ack_r_addr == 1) begin    
												if(sda == 1'b0)				state_next 	= 	WRITE_REG_DATA; 																			
												else if(sda == 1'b1) 		state_next	= 	W_ACK_REG_ADDR; 		end
											else 							state_next	=	W_ACK_REG_ADDR;			end		
				WRITE_REG_DATA	:	begin 	if(cnt_write_reg_data == 15) 	state_next	=	W_ACK_WR_DATA;		
										else 								state_next  = 	WRITE_REG_DATA;			end	
				W_ACK_WR_DATA	:	begin 	if(cnt_ack_w_data == 1) begin 
												if(sda == 1'b0)				state_next 	= 	WRITE_REG_DATA; 													
												else if(sda == 1'b1) 		state_next	= 	STOP; 					end		
											else 							state_next	=	W_ACK_WR_DATA;			end																	
				STOP			:	begin 	if(cnt_stop == 5)				state_next	=	IDLE;			
											else 							state_next	=	STOP;					end
				default			:	begin 	state_next	=	state_next;		end
			endcase
			end
		else if(i2c_config == I2C_Single_Write_Byte) begin 
			case(state_current)	
				IDLE			:	begin 	state_next	=	START; 													end
				START			:	begin 	if(cnt_start == 2) 				state_next	=	DEVICE_ADDR_W;	
											else							state_next	=	START;					end							 			
				DEVICE_ADDR_W	:	begin 	if(cnt_dev_addr == 15)			state_next	=	W_ACK_DEV_ADDR;	
											else							state_next  = 	DEVICE_ADDR_W;			end	 					
				W_ACK_DEV_ADDR	:	begin 	if(cnt_ack_addr == 1) begin 
												if(sda == 1'b0)				state_next 	= 	DEVICE_REG_ADDR;		//若仿真可注释掉本行
												else						state_next  =	W_ACK_DEV_ADDR;			end
											else if(sda == 1'b1) 			state_next	= 	IDLE; 
											else 							state_next	=	W_ACK_DEV_ADDR;			end							
				DEVICE_REG_ADDR	:	begin 	if(cnt_reg_addr == 15)			state_next	=	W_ACK_REG_ADDR;	
											else 							state_next  = 	DEVICE_REG_ADDR;		end								
				W_ACK_REG_ADDR	:	begin 	if(cnt_ack_r_addr == 1) begin    
												if(sda == 1'b0)				state_next 	= 	WRITE_REG_DATA; 		//若仿真可注释掉本行												
												else if(sda == 1'b1) 		state_next	= 	W_ACK_REG_ADDR; 		end
											else 							state_next	=	W_ACK_REG_ADDR;			end		
				WRITE_REG_DATA	:	begin 	if(cnt_write_reg_data == 15) 	state_next	=	W_ACK_WR_DATA;		
											else 							state_next  = 	WRITE_REG_DATA;			end	
				W_ACK_WR_DATA	:	begin 	if(cnt_ack_w_data == 1) begin 
												if(sda == 1'b0)				state_next 	= 	STOP; 					//若仿真可注释掉本行														
											else if(sda == 1'b1) 		state_next	= 	W_ACK_WR_DATA; 			end		
											else 							state_next	=	W_ACK_WR_DATA;			end																	
				STOP			:	begin 	if(cnt_stop == 5) 
													state_next	=	IDLE;	
											else 	state_next	=	STOP;	end
				default			:	begin 	state_next	=	state_next;		end  
			endcase 
			end
		else if(i2c_config == I2C_Single_Read_Byte) begin 
			case(state_current)	
				IDLE			:	begin 	state_next	=	START; 													end
				START			:	begin 	if(cnt_start == 2) 				state_next	=	DEVICE_ADDR_W;	
											else							state_next	=	START;					end							 			
				DEVICE_ADDR_W	:	begin 	if(cnt_dev_addr == 15)			state_next	=	W_ACK_DEV_ADDR;	
											else							state_next  = 	DEVICE_ADDR_W;			end	 					
				W_ACK_DEV_ADDR	:	begin 	if(cnt_ack_addr == 1) begin 
												if(sda == 1'b0)				state_next 	= 	DEVICE_REG_ADDR;		//若仿真可注释
												else						state_next  =	W_ACK_DEV_ADDR;			end
											else if(sda == 1'b1) 			state_next	= 	IDLE; 
											else 							state_next	=	W_ACK_DEV_ADDR;			end							
				DEVICE_REG_ADDR	:	begin 	if(cnt_reg_addr == 15)			state_next	=	W_ACK_REG_ADDR;	
											else 							state_next  = 	DEVICE_REG_ADDR;		end								
				W_ACK_REG_ADDR	:	begin 	if(cnt_ack_r_addr == 1) begin    
												if(sda == 1'b0)				state_next	=	START_R;				//若仿真可注释																											
												else if(sda == 1'b1) 		state_next	= 	W_ACK_REG_ADDR; 		end
											else 							state_next	=	W_ACK_REG_ADDR;			end																	
				START_R			:	begin	if(cnt_start_r == 3) 			state_next	=	DEVICE_ADDR_R;		
											else							state_next	=	START_R;				end	
				DEVICE_ADDR_R	:	begin	if(cnt_dev_addr_r == 15)		state_next	=	W_ACK_DEV_ADDR_R;	
											else							state_next  = 	DEVICE_ADDR_R;			end	 	
				W_ACK_DEV_ADDR_R:	begin 	if(cnt_ack_addr_r == 1) begin 
												if(sda == 1'b0)				state_next 	= 	READ_REG_DATA; 			//若仿真可注释掉本行											
												else if(sda == 1'b1) 		state_next	= 	W_ACK_DEV_ADDR_R; 		end
											else 							state_next	=	W_ACK_DEV_ADDR_R;		end				
				READ_REG_DATA	:	begin	if(cnt_read_reg_data == 15) 	state_next	=	S_NO_ACK;
											else 							state_next  = 	READ_REG_DATA;			end		
				S_NO_ACK		:	begin	if(cnt_s_nack == 1)  			state_next 	= 	STOP; 	
											else							state_next	= 	S_NO_ACK; end	
				STOP			:	begin 	if(cnt_stop == 5) 				state_next	=	IDLE;			
											else 							state_next	=	STOP;	end
				default			:	begin 	state_next	=	state_next;		end
			endcase
			end
		else
			state_next <= state_next;
	end
	

	always@(posedge clk_in or negedge rst_n) begin 
		if(!rst_n) begin 
			sda_ctl	<= 1'b1;
			sda_r	<= 1'b1;
			scl_r	<= 1'b1; 
			cnt_start <= 1'b0;
			cnt_dev_addr <= 1'b0; 
			cnt_ack_addr <= 1'b0; 
			cnt_reg_addr <= 1'b0; 
			cnt_ack_r_addr <= 1'b0; 
			cnt_write_reg_data <= 1'b0;
			cnt_ack_w_data <= 1'b0; 
			cnt_stop <= 1'b0; 
			cnt_s_nack <= 1'b0;	
			cnt_read_reg_data <= 1'b0;	
			cnt_start_r	<= 1'b0;		
			cnt_dev_addr_r <= 1'b0;	
			cnt_ack_addr_r <= 1'b0;	
			cnt_s_ack <= 1'b0; 
			i2c_read_data <= 8'd0; end	
		else begin 	
			case(state_current)
				IDLE			:	begin	sda_ctl	<= 1'b1;
											sda_r	<= 1'b1;
											scl_r	<= 1'b1;	
											cnt_start	 <= 1'b0;
											cnt_dev_addr <= 1'b0; 
											cnt_ack_addr <= 1'b0; 
											cnt_reg_addr <= 1'b0; 
											cnt_ack_r_addr		<= 1'b0; 
											cnt_write_reg_data 	<= 1'b0;
											cnt_ack_w_data 		<= 1'b0; 
											cnt_stop 	<= 1'b0; 
											cnt_s_nack 	<= 1'b0;	
											cnt_read_reg_data 	<= 1'b0;	
											cnt_start_r	<= 1'b0;		
											cnt_dev_addr_r <= 1'b0;	
											cnt_ack_addr_r <= 1'b0;	
											cnt_s_ack <= 1'b0; 
											end
				START			:	begin 	cnt_start	<=	1'b0;
											if(cnt_start > 2) cnt_start <= 1'b0;
											else begin 
												cnt_start <= cnt_start+ 1'b1;
												case(cnt_start)
													0 		: begin scl_r <= 1'b1; sda_ctl <= 1'b1; sda_r <= 1'b1; end
													1 		: begin sda_r <= 1'b0; end
													2 		: begin scl_r <= 1'b0; end
													default	: begin scl_r <= scl_r; sda_ctl <= sda_ctl; sda_r <= sda_r; end
												endcase
											end
									end
				DEVICE_ADDR_W	:	begin 	cnt_dev_addr <= 1'b0;
											if(cnt_dev_addr > 15) cnt_dev_addr <= 1'b0;
											else begin 
												cnt_dev_addr <= cnt_dev_addr + 1'b1; 
												case(cnt_dev_addr)
													0		: begin scl_r <= 1'b0; sda_ctl <= 1'b1;	sda_r <= i2c_device_address[6]; end	
													1		: begin scl_r <= 1'b1; end					
													2		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[5]; end	
													3		: begin scl_r <= 1'b1; end
													4		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[4]; end	
													5		: begin scl_r <= 1'b1; end	
													6		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[3]; end	
													7		: begin scl_r <= 1'b1; end	
													8		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[2]; end	
													9		: begin scl_r <= 1'b1; end	
													10		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[1]; end	
													11		: begin scl_r <= 1'b1; end		
													12		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[0]; end	
													13		: begin scl_r <= 1'b1; end	
													14		: begin scl_r <= 1'b0; sda_r <= 1'b0; end	
													15		: begin scl_r <= 1'b1; end													
													default	: begin scl_r <= scl_r; sda_ctl <= sda_ctl; sda_r <= sda_r; end
												endcase
											end
									end
				W_ACK_DEV_ADDR	:	begin 	cnt_ack_addr <= 1'b0;
											if(cnt_ack_addr > 1) cnt_ack_addr <= 1'b0;
											else begin 
												cnt_ack_addr <= cnt_ack_addr + 1'b1;
												case(cnt_ack_addr)
													0		: begin sda_ctl <= 1'b0; scl_r <= 1'b0;end
													1		: begin scl_r <= 1'b1; end
													default	: begin sda_ctl <= sda_ctl; scl_r <= scl_r; end
												endcase 
											end
									end			
				DEVICE_REG_ADDR	:	begin 	cnt_reg_addr <= 1'b0;
											if(cnt_reg_addr > 15) cnt_reg_addr <= 1'b0;
											else begin 
												cnt_reg_addr <= cnt_reg_addr + 1'b1; 
												case(cnt_reg_addr)
													0		: begin scl_r <= 1'b0; sda_ctl <= 1'b1;	sda_r <= i2c_reg_address[7]; end	
													1		: begin scl_r <= 1'b1; end					
													2		: begin scl_r <= 1'b0; sda_r <= i2c_reg_address[6]; end	
													3		: begin scl_r <= 1'b1; end
													4		: begin scl_r <= 1'b0; sda_r <= i2c_reg_address[5]; end	
													5		: begin scl_r <= 1'b1; end	
													6		: begin scl_r <= 1'b0; sda_r <= i2c_reg_address[4]; end	
													7		: begin scl_r <= 1'b1; end	
													8		: begin scl_r <= 1'b0; sda_r <= i2c_reg_address[3]; end	
													9		: begin scl_r <= 1'b1; end	
													10		: begin scl_r <= 1'b0; sda_r <= i2c_reg_address[2]; end	
													11		: begin scl_r <= 1'b1; end		
													12		: begin scl_r <= 1'b0; sda_r <= i2c_reg_address[1]; end	
													13		: begin scl_r <= 1'b1; end	
													14		: begin scl_r <= 1'b0; sda_r <= i2c_reg_address[0]; end	
													15		: begin scl_r <= 1'b1; end													
													default	: begin scl_r <= scl_r; sda_ctl <= sda_ctl; sda_r <= sda_r; end
												endcase
											end
									end
				W_ACK_REG_ADDR	:	begin 	cnt_ack_r_addr <= 1'b0;
											if(cnt_ack_r_addr > 1) cnt_ack_r_addr <=  1'b0;
											else begin 
												cnt_ack_r_addr <= cnt_ack_r_addr + 1'b1;
												case(cnt_ack_r_addr)
													0		: begin sda_ctl <= 1'b0; scl_r <= 1'b0;end
													1		: begin scl_r <= 1'b1; end
													default	: begin sda_ctl <= sda_ctl; scl_r <= scl_r; end
												endcase 
											end
									end	
				WRITE_REG_DATA	:	begin 	cnt_write_reg_data <= 1'b0;
											if(cnt_write_reg_data > 15) cnt_write_reg_data <=  1'b0;
											else begin 
												cnt_write_reg_data <= cnt_write_reg_data + 1'b1; 
												case(cnt_write_reg_data)
													0		: begin scl_r <= 1'b0; sda_ctl <= 1'b1;	sda_r <= i2c_write_reg_data[7]; end	
													1		: begin scl_r <= 1'b1; end					
													2		: begin scl_r <= 1'b0; sda_r <= i2c_write_reg_data[6]; end	
													3		: begin scl_r <= 1'b1; end
													4		: begin scl_r <= 1'b0; sda_r <= i2c_write_reg_data[5]; end	
													5		: begin scl_r <= 1'b1; end	
													6		: begin scl_r <= 1'b0; sda_r <= i2c_write_reg_data[4]; end	
													7		: begin scl_r <= 1'b1; end	
													8		: begin scl_r <= 1'b0; sda_r <= i2c_write_reg_data[3]; end	
													9		: begin scl_r <= 1'b1; end	
													10		: begin scl_r <= 1'b0; sda_r <= i2c_write_reg_data[2]; end	
													11		: begin scl_r <= 1'b1; end		
													12		: begin scl_r <= 1'b0; sda_r <= i2c_write_reg_data[1]; end	
													13		: begin scl_r <= 1'b1; end	
													14		: begin scl_r <= 1'b0; sda_r <= i2c_write_reg_data[0]; end	
													15		: begin scl_r <= 1'b1; end													
													default	: begin scl_r <= scl_r; sda_ctl <= sda_ctl; sda_r <= sda_r; end
												endcase
											end
									end									
				W_ACK_WR_DATA	:	begin 	cnt_ack_w_data <= 1'b0;
											if(cnt_ack_w_data > 1) cnt_ack_w_data <=  1'b0;
											else begin 
												cnt_ack_w_data <= cnt_ack_w_data + 1'b1;
												case(cnt_ack_w_data)
													0		: begin sda_ctl <= 1'b0; scl_r <= 1'b0;end
													1		: begin scl_r <= 1'b1; end
													default	: begin sda_ctl <= 1'b1; scl_r <= scl_r; end
												endcase 
											end
									end		
	
				START_R			:	begin 	cnt_start_r	<=	1'b0;
											if(cnt_start_r > 3) cnt_start_r <=  1'b0;
											else begin 
												cnt_start_r <= cnt_start_r+ 1'b1;
												case(cnt_start_r)
													0 		: begin scl_r <= 1'b0; sda_ctl <= 1'b1; sda_r <= 1'b1; end
													1 		: begin scl_r <= 1'b1; sda_r <= 1'b1; end
													2		: begin scl_r <= 1'b1; sda_r <= 1'b0; end
													3 		: begin scl_r <= 1'b0; end
													default	: begin scl_r <= scl_r; sda_ctl <= sda_ctl; sda_r <= sda_r; end
												endcase
											end
									end
				DEVICE_ADDR_R	:	begin 	cnt_dev_addr_r <= 1'b0;
											if(cnt_dev_addr_r > 15) cnt_dev_addr_r <=  1'b0;
											else begin 
												cnt_dev_addr_r <= cnt_dev_addr_r + 1'b1; 
												case(cnt_dev_addr_r)
													0		: begin scl_r <= 1'b0; sda_ctl <= 1'b1;	sda_r <= i2c_device_address[6]; end	
													1		: begin scl_r <= 1'b1; end					
													2		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[5]; end	
													3		: begin scl_r <= 1'b1; end
													4		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[4]; end	
													5		: begin scl_r <= 1'b1; end	
													6		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[3]; end	
													7		: begin scl_r <= 1'b1; end	
													8		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[2]; end	
													9		: begin scl_r <= 1'b1; end	
													10		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[1]; end	
													11		: begin scl_r <= 1'b1; end		
													12		: begin scl_r <= 1'b0; sda_r <= i2c_device_address[0]; end	
													13		: begin scl_r <= 1'b1; end	
													14		: begin scl_r <= 1'b0; sda_r <= 1'b1; end	
													15		: begin scl_r <= 1'b1; end													
													default	: begin scl_r <= scl_r; sda_ctl <= sda_ctl; sda_r <= sda_r; end
												endcase
											end
									end
				W_ACK_DEV_ADDR_R:	begin 	cnt_ack_addr_r <= 1'b0;
											if(cnt_ack_addr_r > 1) cnt_ack_addr_r <=  1'b0;
											else begin 
												cnt_ack_addr_r <= cnt_ack_addr_r + 1'b1;
												case(cnt_ack_addr_r)
													0		: begin sda_ctl <= 1'b0; scl_r <= 1'b0;end
													1		: begin scl_r <= 1'b1; end
													default	: begin sda_ctl <= sda_ctl; scl_r <= scl_r; end
												endcase 
											end
									end					
				READ_REG_DATA	:	begin 	sda_ctl <= 1'b0;
											cnt_read_reg_data <= 1'b0;
											if(cnt_read_reg_data > 15) cnt_read_reg_data <=  1'b0;
											else begin 
												cnt_read_reg_data <= cnt_read_reg_data + 1'b1; 
												case(cnt_read_reg_data)
													0		: begin scl_r <= 1'b0; end	
													1		: begin scl_r <= 1'b1; i2c_read_data[7] <= sda; end					
													2		: begin scl_r <= 1'b0; end	
													3		: begin scl_r <= 1'b1; i2c_read_data[6] <= sda; end
													4		: begin scl_r <= 1'b0; end	
													5		: begin scl_r <= 1'b1; i2c_read_data[5] <= sda; end	
													6		: begin scl_r <= 1'b0; end	
													7		: begin scl_r <= 1'b1; i2c_read_data[4] <= sda; end	
													8		: begin scl_r <= 1'b0; end	
													9		: begin scl_r <= 1'b1; i2c_read_data[3] <= sda; end	
													10		: begin scl_r <= 1'b0; end	
													11		: begin scl_r <= 1'b1; i2c_read_data[2] <= sda; end		
													12		: begin scl_r <= 1'b0; end	
													13		: begin scl_r <= 1'b1; i2c_read_data[1] <= sda; end	
													14		: begin scl_r <= 1'b0; end	
													15		: begin scl_r <= 1'b1; i2c_read_data[0] <= sda; end													
													default	: begin scl_r <= scl_r; sda_ctl <= sda_ctl; sda_r <= sda_r; end
												endcase
											end
									end	
				S_NO_ACK		:	begin 	cnt_s_nack	<=	1'b0;
											if(cnt_s_nack > 2) cnt_s_nack <= 1'b0;
											else begin 
												cnt_s_nack <= cnt_s_nack+ 1'b1;
												case(cnt_s_nack)
													0 		: begin scl_r <= 1'b0; sda_ctl <= 1'b1; sda_r <= 1'b1; end
													1 		: begin scl_r <= 1'b1; sda_r <= 1'b1; 	end
													2 		: begin scl_r <= 1'b0; sda_r <= 1'b0;	end
													default	: begin scl_r <= scl_r; sda_ctl <= sda_ctl; sda_r <= sda_r; end
												endcase
											end
									end	
      
				S_ACK_RD_DATA	:	begin 	cnt_s_ack	<=	1'b0;
											if(cnt_s_ack > 2) cnt_s_ack <= 1'b0;
											else begin 
												cnt_s_ack <= cnt_s_ack+ 1'b1;
												case(cnt_s_ack)
													0 		: begin scl_r <= 1'b0; sda_ctl <= 1'b1; sda_r <= 1'b0; end
													1 		: begin scl_r <= 1'b1; sda_r <= 1'b0; 	end
													2 		: begin scl_r <= 1'b0; sda_r <= 1'b0;	end
													default	: begin scl_r <= scl_r; sda_ctl <= sda_ctl; sda_r <= sda_r; end
												endcase
											end
									end	
				
				STOP			:	begin 	cnt_stop	<=	1'b0;
											if(cnt_stop > 5) cnt_stop <=  1'b0;
											else begin 
												cnt_stop <= cnt_stop+ 1'b1;
												case(cnt_stop)
													0 		: begin scl_r <= 1'b0; sda_ctl <= 1'b1; sda_r <= 1'b0; end
													1 		: begin scl_r <= 1'b1; sda_ctl <= 1'b1; end
													2 		: begin sda_r <= 1'b1; sda_ctl <= 1'b1; sda_r <= 1'b1; end
													3 		: begin sda_r <= 1'b1; sda_ctl <= 1'b1; sda_r <= 1'b1; end
													4 		: begin sda_r <= 1'b1; sda_ctl <= 1'b1; sda_r <= 1'b1; end														
													5		: begin ;end	
													default	: begin scl_r <= scl_r; sda_ctl <= 1'b0; sda_r <= sda_r; end
												endcase
											 	
											end
									end
				
				WAIT			:	begin scl_r <= scl_r; sda_ctl <= 1'b0; sda_r <= sda_r; end
									
			endcase
		end
	end
	
	reg	[7:0]	state_debug;
	always @(posedge clk_in or negedge rst_n) begin
		if (!rst_n) begin
			state_debug <= 8'h00;
			write_done  <= 1'b0;
			read_done   <= 1'b0; 
			i2c_ack		<= 8'h00;
			end
		else begin
			case(state_current)	
				IDLE			:	begin 	i2c_ack 	<=	8'h00;
											state_debug <=	8'h01;	
											write_done 	<= 	1'b0;	end
											
				START			:	begin 	i2c_ack 	<=	8'h00;
											state_debug <=	8'h02;	
											write_done 	<= 	1'b0;	end	
											
				DEVICE_ADDR_W	: 	begin 	i2c_ack 	<=	8'h00;
											state_debug <=	8'h03;	end	
					
				W_ACK_DEV_ADDR	:	begin 	i2c_ack 	<=	8'h00;
											state_debug <=	8'h04;	   
											if((cnt_ack_addr == 1'b1) && (!sda) == 1'b1)
												i2c_ack[0]	<= 	1'b1;	
											else 		
												i2c_ack[0]	<= 	1'b0;		
									end
				DEVICE_REG_ADDR	:	begin 	state_debug <=	8'h05;	
											i2c_ack 	<=	8'h00;	end	
					
				W_ACK_REG_ADDR	:	begin 	state_debug <=	8'h06;	
											i2c_ack 	<=	8'h00;	
											if((cnt_ack_r_addr == 1'b1) && (!sda) == 1'b1)
												i2c_ack[1]	<= 	1'b1;	
											else 		
												i2c_ack[1]	<= 	1'b0;												
											end
											
				WRITE_REG_DATA	:	begin 	state_debug <=	8'h07;	
											i2c_ack 	<=	8'h00;	end	
					
				W_ACK_WR_DATA	:	begin 	i2c_ack 	<=	8'h00;
											state_debug <=	8'h08;	
											if((cnt_ack_w_data == 1'b1) && (!sda) == 1'b1) begin
												write_done 	<=	1'b1; 
												i2c_ack[2]	<= 	1'b1;	 end
											else begin 
												write_done	<=	1'b0;	
												i2c_ack[2]	<= 	1'b0;	 end												
									end																	
				START_R			:	begin	i2c_ack 	<=	8'h00;
											state_debug <=	8'h09;	end	
				DEVICE_ADDR_R	:	begin	i2c_ack 	<=	8'h00;
											state_debug <=	8'h0A;	end	 	
				W_ACK_DEV_ADDR_R:	begin 	i2c_ack 	<=	8'h00;
											state_debug <=	8'h0B;	
											if((cnt_ack_addr_r == 1'b1) && (!sda) == 1'b1)
												i2c_ack[3]	<= 	1'b1;	
											else 		
												i2c_ack[3]	<= 	1'b0;												
											end																
				READ_REG_DATA	:	begin	i2c_ack 	<=	8'h00;
											state_debug <=	8'h0C;	end
					
				S_ACK_RD_DATA	:	begin 	i2c_ack 	<=	8'h00;
											state_debug <=	8'h0D;	
											if((cnt_s_ack >= 1'b1) && (cnt_s_ack<2))
												i2c_ack[4]	<= 	1'b1;	
											else 		
												i2c_ack[4]	<= 	1'b0;												
											end		
													
				S_NO_ACK		:	begin	i2c_ack 	<=	8'h00;	
											state_debug <=	8'h0E;	
											read_done	<=	1'b1;	
											if(cnt_s_nack >= 1'b1)
												i2c_ack[5]	<= 	1'b1;	
											else 		
												i2c_ack[5]	<= 	1'b0;												
											end		
											
				STOP			:	begin 	i2c_ack 	<=	8'h00;
											state_debug <=	8'h0F;	
											write_done	<=	1'b0;	
											read_done	<=	1'b0;	end	
									
				WAIT			:	begin 	i2c_ack 	<=	8'h00;
											state_debug	<=  8'h10; 	end
					
				default			:	begin 	state_debug <=	state_debug;	
											write_done	<=	write_done;
											read_done	<=	read_done;
											i2c_ack		<= 	8'h00;	
									end
			endcase
			end
	end
	

	
endmodule


	
									
			
	
	
	
			
			
		
	
	
	
	
	
	
	
	
	
	