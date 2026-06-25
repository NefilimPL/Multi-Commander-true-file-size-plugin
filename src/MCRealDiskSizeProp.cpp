#include "stdafx.h"
#include "MCRealDiskSizeProp.h"
#include "DiskSizeUtil.h"

#ifndef MCREALDISKSIZE_VERSION
#define MCREALDISKSIZE_VERSION "0.1.2.0"
#endif

using namespace MCNS;

namespace
{
    constexpr WORD PROP_REAL_DISK_SIZE = 100;
    constexpr WORD PROP_REAL_DISK_SIZE_RAW = 101;
    constexpr WORD PROP_CLOUD_STATUS = 102;

    WORD g_ExtensionID = 0;

    void CopyWide(WCHAR* dst, size_t dstCount, const WCHAR* src)
    {
        if (!dst || dstCount == 0)
            return;
        StringCchCopyW(dst, dstCount, src ? src : L"");
    }

    void CopyAnsi(char* dst, size_t dstCount, const char* src)
    {
        if (!dst || dstCount == 0)
            return;
        StringCchCopyA(dst, dstCount, src ? src : "");
    }

    std::wstring GetFullPath(IFileItem* item)
    {
        WCHAR path[_MC_MAXPATH_] = {};
        if (!item)
            return L"";
        item->Get_FullPath(path, ARRAYSIZE(path));
        return path;
    }

    bool TryGetCachedAllocatedSize(IFileItem* item, unsigned long long& bytes)
    {
        if (!item || g_ExtensionID == 0)
            return false;

        ExtraProp prop;
        ZeroMemory(&prop, sizeof(ExtraProp));
        if (!item->GetExtraPropData(g_ExtensionID, PROP_REAL_DISK_SIZE, &prop))
            return false;

        if ((prop.Flag & ZFXP_VAL64) == 0 || prop.value64 < 0)
            return false;

        bytes = static_cast<unsigned long long>(prop.value64);
        return true;
    }

    void SetCachedAllocatedSize(IFileItem* item, unsigned long long bytes)
    {
        if (!item || g_ExtensionID == 0 || bytes > static_cast<unsigned long long>(LLONG_MAX))
            return;

        ExtraProp prop;
        ZeroMemory(&prop, sizeof(ExtraProp));
        prop.ClearOnUpdate = true;
        prop.ClearOnRename = true;
        prop.Flag = ZFXP_VAL64;
        prop.value64 = static_cast<INT64>(bytes);
        item->SetExtraPropData(g_ExtensionID, PROP_REAL_DISK_SIZE, &prop);
    }

    MCRealDiskSize::SizeResult GetAllocatedSizeForItem(IFileItem* item, const volatile bool* abortFlag)
    {
        unsigned long long cachedBytes = 0;
        if (TryGetCachedAllocatedSize(item, cachedBytes))
            return { true, cachedBytes, ERROR_SUCCESS };

        const std::wstring path = GetFullPath(item);
        const bool isDirectory = item && item->isFolder();
        MCRealDiskSize::SizeResult result = MCRealDiskSize::GetAllocatedSizeForPath(path, isDirectory, abortFlag);
        if (result.ok)
            SetCachedAllocatedSize(item, result.bytes);

        return result;
    }
}

// Unique 32-char GUID-like identifier, without braces/hyphens, as used by the SDK samples.
char MCRealDiskSizeProp::m_GuidString[34] = "D7227F7059D147B2B65AA39D51334469";

bool MCRealDiskSizeProp::GetExtensionInfo(DLLExtensionInfo* pInfo)
{
    if (!pInfo)
        return false;

    ZeroMemory(pInfo, sizeof(DLLExtensionInfo));
    CopyWide(pInfo->wsName, ARRAYSIZE(pInfo->wsName), L"MCRealDiskSize");
    CopyWide(pInfo->wsPublisher, ARRAYSIZE(pInfo->wsPublisher), L"Kamil / ChatGPT generated source");
    CopyWide(pInfo->wsURL, ARRAYSIZE(pInfo->wsURL), L"https://multicommander.com");
    CopyWide(pInfo->wsDesc, ARRAYSIZE(pInfo->wsDesc), L"Adds columns for real allocated size on disk and OneDrive/Cloud Files state.");
    CopyWide(pInfo->wsBaseName, ARRAYSIZE(pInfo->wsBaseName), L"MCRealDiskSize");
    CopyAnsi(pInfo->strVersion, ARRAYSIZE(pInfo->strVersion), MCREALDISKSIZE_VERSION);
    CopyAnsi(pInfo->strGuid, ARRAYSIZE(pInfo->strGuid), m_GuidString);

#ifdef _UNICODE
    pInfo->dwFlags = EXT_TYPE_PROP | EXT_PREINIT | EXT_NOLANGFILE | EXT_OS_UNICODE;
#else
    pInfo->dwFlags = EXT_TYPE_PROP | EXT_PREINIT | EXT_NOLANGFILE | EXT_OS_ANSI;
#endif
    pInfo->dwInitOrder = 2020;
    // Public MultiCommander SDK currently reports 2.4.0.0, but MC 15.8 rejects that as too old.
    // 2.5.0.0 encoded as: (2 * 1000000) + (5 * 10000) + (0 * 100) + 0.
    // This is a compatibility-test override. Use an official newer SDK when available.
    pInfo->dwInterfaceVersion = 2050000;
    return true;
}

char* MCRealDiskSizeProp::Get_ModuleID()
{
    return m_GuidString;
}

long MCRealDiskSizeProp::PreStartInit(IMultiAppInterface* pAppInterface)
{
    if (!pAppInterface)
        return 0;

    IFilePropertiesManager* propMan = static_cast<IFilePropertiesManager*>(pAppInterface->QueryInterface(ZOBJ_PROPMANGER, 0));
    if (!propMan)
        return 0;

    propMan->Init(m_GuidString);

    FilePropData fpd;
    ZeroMemory(&fpd, sizeof(FilePropData));
    fpd.PropertyId = PROP_REAL_DISK_SIZE;
    fpd.IdealWidth = 95;
    fpd.Align = DT_RIGHT;
    // Keep this as STRING for MC 15.8 compatibility: numeric properties may load
    // but render blank with the public SDK compatibility shim. GetPropStr returns
    // a zero-padded byte key for sorting; GetDisplayValue shows readable text.
    fpd.dwOptions = FILEPROP_STRING |
                    FILEPROP_ASYNC |
                    FILEPROP_CUSTOMIZABLE |
                    FILEPROP_DONOTCACHEASDISPLAY |
                    FILEPROP_CLEAR_IF_UPDATED |
                    FILEPROP_CLEAR_IF_RENAMED;
    fpd.szPropName = L"MCRealDiskSize.Allocated";
    fpd.szDisplayName = L"Rozmiar na dysku";
    fpd.szColumnName = L"Na dysku";
    fpd.szCategoryName = L"Real Disk Size";
    fpd.szDescription = L"Real allocated size on local disk. Useful for OneDrive Files On-Demand, sparse and compressed files.";
    propMan->RegisterProperty(&fpd);

    ZeroMemory(&fpd, sizeof(FilePropData));
    fpd.PropertyId = PROP_REAL_DISK_SIZE_RAW;
    fpd.IdealWidth = 120;
    fpd.Align = DT_RIGHT;
    // RAW is also returned as STRING. It is zero-padded to 20 digits, so string sorting
    // still works numerically for values below 100 EB.
    fpd.dwOptions = FILEPROP_STRING |
                    FILEPROP_ASYNC |
                    FILEPROP_CUSTOMIZABLE |
                    FILEPROP_NOTINMENU |
                    FILEPROP_CLEAR_IF_UPDATED |
                    FILEPROP_CLEAR_IF_RENAMED;
    fpd.szPropName = L"MCRealDiskSize.AllocatedBytes";
    fpd.szDisplayName = L"Rozmiar na dysku RAW";
    fpd.szColumnName = L"Na dysku RAW";
    fpd.szCategoryName = L"Real Disk Size";
    fpd.szDescription = L"Real allocated size in bytes. Use this column when you need exact numeric sorting/filtering.";
    propMan->RegisterProperty(&fpd);

    ZeroMemory(&fpd, sizeof(FilePropData));
    fpd.PropertyId = PROP_CLOUD_STATUS;
    fpd.IdealWidth = 180;
    fpd.Align = DT_LEFT;
    fpd.dwOptions = FILEPROP_STRING |
                    FILEPROP_ASYNC |
                    FILEPROP_CUSTOMIZABLE |
                    FILEPROP_CLEAR_IF_UPDATED |
                    FILEPROP_CLEAR_IF_RENAMED;
    fpd.szPropName = L"MCRealDiskSize.CloudStatus";
    fpd.szDisplayName = L"Status lokalny/OneDrive";
    fpd.szColumnName = L"Status dysku";
    fpd.szCategoryName = L"Real Disk Size";
    fpd.szDescription = L"Shows selected Windows/Cloud Files attributes such as ONLINE_ONLY, PINNED, UNPINNED, OFFLINE.";
    propMan->RegisterProperty(&fpd);

    pAppInterface->ReleaseInterface(reinterpret_cast<ZHANDLE>(propMan), ZOBJ_PROPMANGER);
    g_ExtensionID = pAppInterface->ModuleIDStrToID(m_GuidString);
    return 0;
}

bool MCRealDiskSizeProp::Open(IFileItem* /*pParentFileItem*/)
{
    return true;
}

bool MCRealDiskSizeProp::Open(const WCHAR* /*szParentPath*/)
{
    return true;
}

bool MCRealDiskSizeProp::Close()
{
    return true;
}

bool MCRealDiskSizeProp::GetDisplayValue(IFileItem* pFileItem, WCHAR* propData, WORD nLen, WORD PropertyId, const volatile bool* pAbort)
{
    if (!pFileItem || !propData || nLen == 0)
        return false;

    if (PropertyId != PROP_REAL_DISK_SIZE)
        return false;

    MCRealDiskSize::SizeResult result = GetAllocatedSizeForItem(pFileItem, pAbort);
    if (!result.ok)
    {
        propData[0] = L'\0';
        return true;
    }

    const std::wstring formatted = MCRealDiskSize::FormatBytes(result.bytes);
    StringCchCopyW(propData, nLen, formatted.c_str());
    return true;
}

bool MCRealDiskSizeProp::GetPropStr(IFileItem* pFileItem, WCHAR* propData, WORD nLen, WORD PropertyId, const volatile bool* pAbort)
{
    if (!pFileItem || !propData || nLen == 0)
        return false;

    if (PropertyId == PROP_REAL_DISK_SIZE || PropertyId == PROP_REAL_DISK_SIZE_RAW)
    {
        MCRealDiskSize::SizeResult result = GetAllocatedSizeForItem(pFileItem, pAbort);

        if (!result.ok)
        {
            propData[0] = L'\0';
            return true;
        }

        // Zero-padded text keeps lexicographic sorting aligned with numeric sorting.
        StringCchPrintfW(propData, nLen, L"%020llu", result.bytes);
        return true;
    }

    if (PropertyId == PROP_CLOUD_STATUS)
    {
        const std::wstring path = GetFullPath(pFileItem);
        const std::wstring status = MCRealDiskSize::GetCloudStatusText(path, pFileItem);
        StringCchCopyW(propData, nLen, status.c_str());
        return true;
    }

    return false;
}

bool MCRealDiskSizeProp::GetPropNum(IFileItem* pFileItem, INT64* propData, WORD PropertyId, const volatile bool* pAbort)
{
    if (!pFileItem || !propData)
        return false;

    if (PropertyId != PROP_REAL_DISK_SIZE && PropertyId != PROP_REAL_DISK_SIZE_RAW)
        return false;

    MCRealDiskSize::SizeResult result = GetAllocatedSizeForItem(pFileItem, pAbort);
    if (!result.ok)
        return false;

    if (result.bytes > static_cast<unsigned long long>(LLONG_MAX))
        *propData = LLONG_MAX;
    else
        *propData = static_cast<INT64>(result.bytes);

    return true;
}

bool MCRealDiskSizeProp::GetPropDouble(IFileItem* /*pFileItem*/, double* /*propData*/, WORD /*PropertyId*/, const volatile bool* /*pAbort*/)
{
    return false;
}

bool MCRealDiskSizeProp::FormatDisplayValue(WCHAR* szDisplayValue, WORD nLen, INT64 nValue, WORD PropertyId)
{
    if (!szDisplayValue || nLen == 0)
        return false;

    if (PropertyId != PROP_REAL_DISK_SIZE)
        return false;

    if (nValue < 0)
        return false;

    const std::wstring formatted = MCRealDiskSize::FormatBytes(static_cast<unsigned long long>(nValue));
    StringCchCopyW(szDisplayValue, nLen, formatted.c_str());
    return true;
}

bool MCRealDiskSizeProp::SetProp(IFileItem* /*pFileItem*/, WORD /*PropertyId*/, const BYTE* /*propData*/)
{
    return false;
}
