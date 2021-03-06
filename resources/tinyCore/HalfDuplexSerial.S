/* optimized half-duplex serial uart implementation - 27 instructions
 * @author: Ralph Doncaster 2014
 * @version: $Id$
 *
 * Modified by J.Sleeman (sparks@gogo.co.nz) to add Non Blocking reads
 *   RxByteNBZeroReturn   (returns BYTE 0 for no data [or null byte read])
 *   RxByteNBNegOneReturn (returns INT -1 for no data)
 * if not used these should be optimized out automatically by the linker.
 */

/* Notes:

   ATtiny 4/5/9/10 Datasheet Page 17
   " ATtiny4/5/9/10 implement only 16 registers. For reasons of compatibility the registers are numbered R16...R31, not R0...R15."
   
   https://gcc.gnu.org/wiki/avr-gcc
   R18–R27, R30, R31
   These GPRs are call clobbered. An ordinary function may use them without restoring the contents. Interrupt service routines (ISRs) must save and restore each register they use.
 */
/* needed for <avr/io.h> to give io constant addresses */
#define __SFR_OFFSET 0
#include <avr/io.h>

#ifdef PORTD
#define UART_Port PORTD
#else
#define UART_Port PORTB
#endif
#define UART_Tx 0
#define UART_Rx 1

#define delayArg r22

// #define outRegister r0
#define outRegister r18
.extern TXDELAY
.section .text.transmit,"ax",@progbits
; transmit byte contained in r24
; AVR305 has 1 cycle of jitter per bit, this has none
.global TxByte
TxByte:
  cli
  sbi UART_Port-1, UART_Tx    ; set Tx line to output
  cbi UART_Port, UART_Tx      ; start bit
  in outRegister, UART_Port
  ldi r25, 7            ; stop bit & idle state
TxLoop:
  ; 8 cycle loop + delay = 7 + 3*DelayArg
  ldi delayArg, TXDELAY
TxDelay:
    dec delayArg
  brne TxDelay
  bst r24, 0            ; store lsb in T
  bld outRegister, UART_Tx
  lsr r25
  ror r24             ; 2-byte shift register
  out UART_Port, outRegister
  brne TxLoop
  sei
  ret

  
.extern RXSTART
.extern RXDELAY

.section .text.receive,"ax",@progbits
; receive byte into r24
.global RxByte

RxByte:
  sbic UART_Port-2, UART_Rx   ; wait for start edge  
  rjmp RxByte    
GotStartBit:
  push r16
  in r16, SREG; Save status register 
  cli ; Clear interrupts - if we allow interrupts here (eg for millis) we lose bits
  ldi r24, 0x80         ; bit shift counter
  ldi delayArg, RXSTART     ; 1.5 bit delay
RxBit:
  ; 7 cycle loop + delay = 7 + 6 + 3*DelayArg
  rcall Delay3Cycle       ; delay and clear carry
  ldi delayArg, RXDELAY 
  lsr r24
  sbic UART_Port-2, UART_Rx
  ori r24, 0x80
    nop                             ; match 7-cycle Tx loop
  brcc RxBit
  ; fall into delay for stop bit
  out SREG, r16 ; Return status register, this enables interrupts again
  pop r16

; delay (3 cycle * delayArg) -1 + 4 cycles (ret instruction)
Delay3Cycle:
  dec delayArg
  brne Delay3Cycle
  ret

; We put these in their own section so the linker can drop them
; if not used.
.section .text.receivenb,"ax",@progbits
.global RxByteNBNegOneReturn
.global RxByteNBZeroReturn
; Non-Blocking RX Byte with zero return
RxByteNBZeroReturn:
  sbic UART_Port-2, UART_Rx   ; wait for start edge
  rjmp NoWaitRxZeroReturn     ; if no start, drop out with a zero return
  rjmp GotStartBit            ; otherwise read the byte in
   
RxByteNBNegOneReturn:
  sbic UART_Port-2, UART_Rx   ; wait for start edge
  rjmp NoWaitRxNegOneReturn   ; if no start, drop out with a zero return
  ldi r25, 0x00               ; this routine will return an int, 
                              ; because Serial.write() does normally return -1 when no data is read
                              ; since we are returning data set the upper byte of the int to zero
  rjmp GotStartBit            ; read the bit in

NoWaitRxNegOneReturn:
  ldi r25, 0xFF     ; In non blocking mode we follow the standard "Serial.read()" return value of
  ldi r24, 0xFF     ; -1 indicates no data read  ( signed int, 0xFFFF <-- [0x0000] --> 0x0001 )
  ret

NoWaitRxZeroReturn:  
  ldi r24, 0x00     ; 0 indicates no data read
  ret
