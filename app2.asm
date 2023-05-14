SECTION header vstart=0
    program_length dd program_end
    code_entry dw start
               dd section.code.start
    realloc_tbl_len dw (header_end-realloc_begin)/4

    realloc_begin:
    code_segment dd section.code.start
    ;data_segment dd section.data.start
    stack_segment dd section.stack.start

    header_end:

SECTION code align=16 vstart=0
    new_int_0x70:     ;rtc 中断函数入口
        push ax
        push bx
        push cx
        push dx
        push ds

    .w0:
        mov al,0x0a   ;读rtc寄存器A的命令
        or al,0x80    ;0x70端口 第7位设置，阻断NMI
        out 0x70,al
        in al,0x71    ;读rtc A 寄存器，
        test al,0x80  ;第7位为1，更新过程中，不可操作
        jnz .w0

        mov al,0x80  ;读rtc 寄存器 0命令,阻断NMI
        out 0x70,al   
        in al,0x71    ;寄存器0是
        push ax

        mov al,0x82  ; 寄存器2 
        out 0x70,al
        in al,0x71   ;分
        push ax

        mov al,0x84 ;4
        out 0x70,al
        in al,0x71  ;时
        push ax

        mov al,0x0c  ;寄存器c,打开NMI
        out 0x70,al
        in al,0x71   ;7位是中断请求标志，6是周期性中断标志，5是闹钟中断标志，4是更新结束标志。本代码只初始化设置了跟新结束中断，所以不判断中断

        mov ax,0xb800
        mov es,ax   ;显存段地址

        pop ax      ;时
        call bcd_to_ascii
        mov bx,12*160 + 36*2 ;显存偏移位置，第12行第36个位置
        mov [es:bx],ah
        mov [es:bx+2],al

        mov byte [es:bx+4],':'
        pop ax      ;分
        call bcd_to_ascii
        mov [es:bx+6],ah
        mov [es:bx+8],al

        mov byte [es:bx+10],':'
        not byte [es:bx+11]

        pop ax     ;秒
        call bcd_to_ascii
        mov [es:bx+12],ah
        mov [es:bx+14],al



        mov al,0x20   ;中断结束命令eoi
        out 0xa0,al   ;从中断控制器
        out 0x20,al   ;主中断控制器

        pop es
        pop dx
        pop cx
        pop bx
        pop ax

        iret


    bcd_to_ascii:   ;al是输入2个bcd码，ah,al是输出2个ascii
        mov ah,al

        and al,0x0f
        add al,0x30

        and ah,0xf0
        shr ah,4
        add ah,0x30

       ret 

    start:
        mov ax,[stack_segment]
        mov ss,ax
        mov sp,ss_pointer
        

        mov al,0x70
        mov bl,4
        mul bl   ;0x70号中断，每个中断占用4个字节存放中断处理程序的函数指针
        mov bx,ax
        
        cli      ;flags 屏蔽可屏蔽中断

        push es
        mov ax,0x00
        mov es,ax
        mov word [es:bx],new_int_0x70 ;两个字节的偏移
        mov word [es:bx+2],cs
        pop es


        ;设置rtc中断
        mov al,0x8b
        out 0x70,al   ;操作rtc b寄存器命令，阻断nmi
        mov al,0x12   ; 7位0 更新操作每秒一次，6：0周期中断禁止，5：0闹钟中断禁止，4：1更新结束中断允许,2:0 bcd码，1:1 24小时制
        out 0x71,al

        mov al,0x0c
        out 0x70,al   ;操作寄存器c命令，放开nmi
        in al,0x71     ;读c内容 清空标志

        sti           ;flags, 打开可屏蔽中断


        ;显示@
        mov cx,0xb800
        mov ds,cx
        mov byte [12*60+33*2],'@'

    .idle:
        hlt             ;挂起，中断唤醒
        not byte [12*160+33*2+1] ;格式信息翻转，白底黑字
        jmp .idle
SECTION stack align=16 vstart=0
    resb 256
ss_pointer:


program_end: