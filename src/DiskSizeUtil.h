#pragma once
#include "stdafx.h"

namespace MCRealDiskSize
{
    struct SizeResult
    {
        bool ok = false;
        unsigned long long bytes = 0;
        DWORD lastError = ERROR_SUCCESS;
    };

    SizeResult GetAllocatedSizeForPath(const std::wstring& path, bool isDirectory, const volatile bool* abortFlag);
    std::wstring FormatBytes(unsigned long long bytes);
    std::wstring GetCloudStatusText(const std::wstring& path, const MCNS::IFileItem* fileItem);
}
