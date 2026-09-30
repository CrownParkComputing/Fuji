//
//  Shifter-Bridging-Header.h
//
//  The whole Swift side of Shifter talks to the emulator core through the plain-C
//  ABI declared here. The header is found by bare name because the target's
//  HEADER_SEARCH_PATHS includes core/retro/bridge (set in cmake/shifter-app.cmake).
//

#import "atarist_bridge.h"
