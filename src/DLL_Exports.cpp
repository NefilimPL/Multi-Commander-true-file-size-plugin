#include "stdafx.h"
#include "MCRealDiskSizeProp.h"

#ifdef _MANAGED
#pragma managed(push, off)
#endif

BOOL APIENTRY DllMain(HMODULE /*hModule*/, DWORD reason, LPVOID /*reserved*/)
{
    switch (reason)
    {
    case DLL_PROCESS_ATTACH:
    case DLL_THREAD_ATTACH:
    case DLL_THREAD_DETACH:
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}

extern "C" PVOID APIENTRY Create(int nID)
{
    if (nID == 0)
        return static_cast<MCNS::IFileProperties*>(new MCNS::MCRealDiskSizeProp());
    return nullptr;
}

extern "C" bool APIENTRY Delete(PVOID pModule, int nID)
{
    if (!pModule)
        return false;

    if (nID == 0)
    {
        delete static_cast<MCNS::MCRealDiskSizeProp*>(pModule);
        return true;
    }

    return false;
}

extern "C" bool APIENTRY GetExtensionInfo(int nID, MCNS::DLLExtensionInfo* pInfo)
{
    if (nID == 0)
        return MCNS::MCRealDiskSizeProp::GetExtensionInfo(pInfo);
    return false;
}

#ifdef _MANAGED
#pragma managed(pop)
#endif
