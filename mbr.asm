app_lba_start equ 100

SECTION mbr align=16 vstart=0x7c00                                     

         ;设置堆栈段和栈指针 
         mov ax,0      
         mov ss,ax
         mov sp,ax
      
         mov ax,[cs:phy_base]            ;计算用于加载用户程序的逻辑段地址 
         mov dx,[cs:phy_base+0x02]
         mov bx,16        
         div bx            
         mov ds,ax                       ;令DS和ES指向该段以进行操作
         mov es,ax                        
    
         ;以下读取程序的起始部分 
         xor di,di
         mov si,app_lba_start            ;程序在硬盘上的起始逻辑扇区号 
         xor bx,bx                       ;加载到DS:0x0000处 
         call read_hard_disk_0

         mov dx,[2]          ;dx = ds:2
         mov ax,[0]
         mov bx,512
         div bx
         cmp dx,0
         jnz @1          ;dx != 0，则有ax+1个扇区,还要读ax个扇区
         dec ax
       @1:
         cmp ax,0    ;不足512个字节，上一个读扇区，已经读完
         jz direct

         push ds
         mov cx,ax
       @2:
         mov ax,ds
         add ax,0x20 ;ds+0x20 ds:bx 缓冲地址加512
         mov ds,ax

         xor bx,bx
         inc si
         call read_hard_disk_0
         loop @2

         pop ds
       
       direct:
         mov dx,[0x08]
         mov ax,[0x06]     ;dx:ax 是section.code_1.start的汇编地址
         call calc_segment_base  ;返回ax为 dx:ax 在内存中的段地址
         mov [0x06],ax

         mov cx,[0x0a]   ;app section number
         mov bx,0x0c    

       realloc:
         mov dx,[bx+0x02] 
         mov ax,[bx]          ;dx:ax 是section.code_1.start的汇编地址
         call calc_segment_base
         mov [bx],ax
         add bx,4
         loop realloc
         jmp far [0x04]   ;间接绝对远跳转


;传入以[phy_base]为起始的汇编地址，计算她的段地址,ax为返回值
calc_segment_base:                        ;计算16位段地址
       push dx
       add ax,[cs:phy_base]
       add dx,[cs:phy_base+0x02]  ;dx:ax + 32位数
       shr ax,4      ; 右移4位
       ror dx,4      ;循环右移4位
       and dx, 0xf000
       or ax,dx  ;保留了dx:ax  dx[0-4]:ax[4-16] 作为传入地址的段地址

       pop dx
       ret



read_hard_disk_0:                        ;从硬盘读取一个逻辑扇区
                                         ;输入：DI:SI=起始逻辑扇区号
                                         ;      DS:BX=目标缓冲区地址
         push ax
         push bx
         push cx
         push dx
      
         mov dx,0x1f2
         mov al,1
         out dx,al                       ;读取的扇区数

         inc dx                          ;0x1f3
         mov ax,si
         out dx,al                       ;LBA地址7~0

         inc dx                          ;0x1f4
         mov al,ah
         out dx,al                       ;LBA地址15~8

         inc dx                          ;0x1f5
         mov ax,di
         out dx,al                       ;LBA地址23~16

         inc dx                          ;0x1f6
         mov al,0xe0                     ;LBA28模式，主盘
         or al,ah                        ;LBA地址27~24
         out dx,al

         inc dx                          ;0x1f7
         mov al,0x20                     ;读命令
         out dx,al

  .waits:
         in al,dx
         and al,0x88
         cmp al,0x08
         jnz .waits                      ;不忙，且硬盘已准备好数据传输 

         mov cx,256                      ;总共要读取的字数
         mov dx,0x1f0
  .readw:
         in ax,dx
         mov [bx],ax
         add bx,2
         loop .readw

         pop dx
         pop cx
         pop bx
         pop ax
      
         ret

phy_base:
     dd 0x10000             ;用户程序被加载的物理起始地址
         
times 510-($-$$) db 0
db 0x55,0xaa