#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = Av4::Ansi  PACKAGE = Av4::Ansi

unsigned char
getcolor(clrchar)
    unsigned char clrchar
    INIT:
        unsigned char __colors[8] = "xrgybpcw";
        char i = 0;
    CODE:
        RETVAL = -1;
        for ( i = 0; i < 8; i++ ) {
            if (   clrchar     == __colors[i] ) { RETVAL = i; break; }
            if ( ( clrchar+32) == __colors[i] ) { RETVAL = i; break; }
        }
    OUTPUT:
        RETVAL

