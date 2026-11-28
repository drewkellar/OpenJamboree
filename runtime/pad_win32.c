/* SwitchRecomp - Copyright 2026 MZ Labs
   Licensed under the GNU Affero General Public License v3.0, see LICENSE.txt and NOTICE.txt.
   Forks and derived works have to keep the credit to SwitchRecomp by MZ Labs and the startup screen. */
#include "rt.h"
#include <stdbool.h>
#include <wchar.h>
#include <windows.h>

/* Optional SDL3 gamepad ABI, loaded from the install or game directory.
   Enum values follow SDL3's SDL_gamepad.h and SDL_init.h. */
typedef struct SDL_Gamepad SDL_Gamepad;
enum { SDL_INIT_GAMEPAD=0x2000, SWITCH_PRO=7, SWITCH_JOYCON_PAIR=10 };
enum { SOUTH, EAST, WEST, NORTH, BACK, GUIDE, START, LS, RS, LB, RB, UP, DOWN, LEFT, RIGHT };
static struct {
  bool (*init)(u32);
  bool (*hint)(const char*,const char*);
  void (*pump)(void);
  void (*flush)(u32,u32);
  u32* (*list)(int*);
  void (*free)(void*);
  int (*type)(u32);
  SDL_Gamepad* (*open)(u32);
  void (*close)(SDL_Gamepad*);
  bool (*connected)(SDL_Gamepad*);
  bool (*button)(SDL_Gamepad*,int);
  i16 (*axis)(SDL_Gamepad*,int);
} sdl;

static HMODULE sdl_gamepad_library(void){
  wchar_t path[32768];
  DWORD len=GetModuleFileNameW(NULL,path,sizeof path/sizeof *path);
  if(!len || len>=sizeof path/sizeof *path) return NULL;
  wchar_t* base=wcsrchr(path,L'\\');
  if(!base || (size_t)(base-path)+20>=sizeof path/sizeof *path) return NULL;
  wcscpy(base+1,L"SDL3.dll");
  HMODULE dll=LoadLibraryExW(path,NULL,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
  if(!dll){
    wcscpy(base+1,L"..\\lib\\SDL3.dll");
    dll=LoadLibraryExW(path,NULL,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
  }
  return dll;
}

void win_gamepads_init(void){
  HMODULE dll=sdl_gamepad_library();
  if(!dll) return;
#define SDL_LOAD(field,name) do { sdl.field=(void*)GetProcAddress(dll,name); if(!sdl.field) goto failed; } while(0)
  SDL_LOAD(init,"SDL_Init");
  SDL_LOAD(hint,"SDL_SetHint");
  SDL_LOAD(pump,"SDL_PumpEvents");
  SDL_LOAD(flush,"SDL_FlushEvents");
  SDL_LOAD(list,"SDL_GetGamepads");
  SDL_LOAD(free,"SDL_free");
  SDL_LOAD(type,"SDL_GetRealGamepadTypeForID");
  SDL_LOAD(open,"SDL_OpenGamepad");
  SDL_LOAD(close,"SDL_CloseGamepad");
  SDL_LOAD(connected,"SDL_GamepadConnected");
  SDL_LOAD(button,"SDL_GetGamepadButton");
  SDL_LOAD(axis,"SDL_GetGamepadAxis");
#undef SDL_LOAD
  /* Win32 owns the window, so SDL has no window focus of its own. Polling is
     gated by the Win32 window's focus and is disabled for background tests. */
  sdl.hint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS","1");
  if(sdl.init(SDL_INIT_GAMEPAD)){
    LOG("input: SDL3 gamepads enabled (Nintendo/Xbox layout follows the active pad)\n");
    return;
  }
failed:
  memset(&sdl,0,sizeof sdl);
  FreeLibrary(dll);
  WARN("input: SDL3 gamepads unavailable, using XInput\n");
}

typedef struct { i32 sticks[4]; u64 buttons; } PadSample;
typedef struct { SDL_Gamepad* pad; u32 id; int nintendo; PadSample previous; } WinPad;
static WinPad pads[8];
static int active_pad=-1;

static void scan_gamepads(void){
  int count=0;
  u32* ids=sdl.list(&count);
  if(!ids) return;
  for(int i=0;i<count;i++){
    int existing=0, free_slot=-1;
    for(int slot=0;slot<8;slot++){
      if(pads[slot].id==ids[i]) existing=1;
      if(!pads[slot].pad && free_slot<0) free_slot=slot;
    }
    if(existing || free_slot<0) continue;
    SDL_Gamepad* gamepad=sdl.open(ids[i]);
    if(!gamepad) continue;
    int type=sdl.type(ids[i]);
    pads[free_slot]=(WinPad){.pad=gamepad,.id=ids[i],.nintendo=type>=SWITCH_PRO && type<=SWITCH_JOYCON_PAIR};
  }
  sdl.free(ids);
}

static PadSample gamepad_sample(SDL_Gamepad* pad){
  PadSample sample={0};
  static const int bits[]={0,1,2,3,11,-1,10,4,5,6,7,13,15,12,14};
  for(int i=SOUTH;i<=RIGHT;i++)
    if(bits[i]>=0 && sdl.button(pad,i)) sample.buttons|=1ull<<bits[i];
  for(int i=0;i<4;i++) sample.sticks[i]=sdl.axis(pad,i);
  if(sdl.axis(pad,4)>7700) sample.buttons|=1ull<<8;
  if(sdl.axis(pad,5)>7700) sample.buttons|=1ull<<9;
  return sample;
}

static int gamepad_activity(const PadSample* now, const PadSample* previous){
  if(now->buttons & ~previous->buttons) return 1;
  for(int i=0;i<4;i++)
    if(abs(now->sticks[i])>=13000 &&
       (abs(previous->sticks[i])<13000 || abs(now->sticks[i]-previous->sticks[i])>=8000)) return 1;
  return 0;
}

static u64 face_positions(u64 b){
  return (b&~15ull)|((b&0xA)>>1)|((b&5)<<1); /* south/east and west/north swap */
}

static i32 y_axis(i32 v){ return v==-32768? 32767 : -v; }

int win_gamepads_poll(int by_position, PadState* out, int* xbox_layout){
  if(!sdl.pump) return 0;
  sdl.pump();
  sdl.flush(0,0xFFFF);
  for(int i=0;i<8;i++) if(pads[i].pad && !sdl.connected(pads[i].pad)){
    sdl.close(pads[i].pad);
    pads[i]=(WinPad){0};
    if(active_pad==i) active_pad=-1;
  }
  static u64 next_scan;
  u64 now=plat_ns();
  if(now>=next_scan){ scan_gamepads(); next_scan=now+500000000ull; }
  int first=-1, used=-1;
  for(int i=0;i<8;i++) if(pads[i].pad){
    if(first<0) first=i;
    PadSample sample=gamepad_sample(pads[i].pad);
    if(gamepad_activity(&sample,&pads[i].previous) &&
       (used<0 || pads[i].nintendo>pads[used].nintendo ||
        (pads[i].nintendo==pads[used].nintendo && i==active_pad))) used=i;
    pads[i].previous=sample;
  }
  if(used>=0) active_pad=used;
  if(active_pad<0) active_pad=first;
  if(active_pad<0){
    *xbox_layout=!by_position;
    return 0;
  }
  WinPad* pad=&pads[active_pad];
  *xbox_layout=!by_position && !pad->nintendo;
  const PadSample* sample=&pad->previous;
  out->buttons=*xbox_layout? sample->buttons : face_positions(sample->buttons);
  out->lx=sample->sticks[0]; out->ly=y_axis(sample->sticks[1]);
  out->rx=sample->sticks[2]; out->ry=y_axis(sample->sticks[3]);
  return 1;
}
