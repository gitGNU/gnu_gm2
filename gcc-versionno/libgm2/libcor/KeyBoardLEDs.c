/* Copyright (C) 2005, 2006, 2007, 2008, 2009, 2010, 2011, 2012, 2013,
 *               2014
 *               Free Software Foundation, Inc. */
/* This file is part of GNU Modula-2.

GNU Modula-2 is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 3, or (at your option) any later
version.

GNU Modula-2 is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License along
with gm2; see the file COPYING.  If not, write to the Free Software
Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA. */

#if defined(linux)

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <linux/kd.h>

#if !defined(TRUE)
#   define TRUE (1==1)
#endif
#if !defined(FALSE)
#   define FALSE (1==0)
#endif

#include <stdlib.h>

static int fd;
static int initialized = FALSE;


void KeyBoardLEDs_SwitchScroll (int scrolllock)
{
  unsigned char leds;
  int r = ioctl(fd, KDGETLED, &leds);
  if (scrolllock)
    leds = leds | LED_SCR;
  else
    leds = leds & (~ LED_SCR);
  r = ioctl(fd, KDSETLED, leds);
}

void KeyBoardLEDs_SwitchNum (int numlock)
{
  unsigned char leds;
  int r = ioctl(fd, KDGETLED, &leds);
  if (numlock)
    leds = leds | LED_NUM;
  else
    leds = leds & (~ LED_NUM);
  r = ioctl(fd, KDSETLED, leds);
}

void KeyBoardLEDs_SwitchCaps (int capslock)
{
  unsigned char leds;
  int r = ioctl(fd, KDGETLED, &leds);
  if (capslock)
    leds = leds | LED_CAP;
  else
    leds = leds & (~ LED_CAP);
  r = ioctl(fd, KDSETLED, leds);
}

void KeyBoardLEDs_SwitchLeds (int numlock, int capslock, int scrolllock)
{
  KeyBoardLEDs_SwitchScroll(scrolllock);
  KeyBoardLEDs_SwitchNum(numlock);
  KeyBoardLEDs_SwitchCaps(capslock);
}

_M2_KeyBoardLEDs_init (void)
{
  if (! initialized) {
    initialized = TRUE;
    fd = open("/dev/tty", O_RDONLY);
    if (fd == -1) {
      perror("unable to open /dev/tty");
      exit(1);
    }
  }
}

#else
void KeyBoardLEDs_SwitchLeds (int numlock, int capslock, int scrolllock)
{
}

void SwitchScroll (int scrolllock)
{
}

void SwitchNum (int numlock)
{
}

void SwitchCaps (int capslock)
{
}

void _M2_KeyBoardLEDs_init (void)
{
}

#endif

void _M2_KeyBoardLEDs_finish (void)
{
}
