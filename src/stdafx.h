#pragma once

#ifndef WINVER
#define WINVER 0x0A00
#endif

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#ifndef NOMINMAX
#define NOMINMAX
#endif

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#define _CRT_SECURE_NO_WARNINGS

#include <windows.h>
#include <strsafe.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cstdint>
#include <cwctype>
#include <climits>

// Multi Commander SDK include path is supplied by the Visual Studio project via MCSDKDir.
#include "FilePropertiesPlugin.h"
