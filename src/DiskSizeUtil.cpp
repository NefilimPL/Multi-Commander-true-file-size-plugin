#include "stdafx.h"
#include "DiskSizeUtil.h"

#ifndef FILE_ATTRIBUTE_PINNED
#define FILE_ATTRIBUTE_PINNED 0x00080000
#endif

#ifndef FILE_ATTRIBUTE_UNPINNED
#define FILE_ATTRIBUTE_UNPINNED 0x00100000
#endif

#ifndef FILE_ATTRIBUTE_RECALL_ON_OPEN
#define FILE_ATTRIBUTE_RECALL_ON_OPEN 0x00040000
#endif

#ifndef FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS
#define FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS 0x00400000
#endif

#ifndef IO_REPARSE_TAG_SYMLINK
#define IO_REPARSE_TAG_SYMLINK (0xA000000CL)
#endif

#ifndef IO_REPARSE_TAG_MOUNT_POINT
#define IO_REPARSE_TAG_MOUNT_POINT (0xA0000003L)
#endif

namespace MCRealDiskSize
{
    namespace
    {
        bool IsAbortRequested(const volatile bool* abortFlag)
        {
            return abortFlag != nullptr && *abortFlag;
        }

        bool StartsWith(const std::wstring& value, const wchar_t* prefix)
        {
            const size_t n = wcslen(prefix);
            if (value.size() < n)
                return false;
            return _wcsnicmp(value.c_str(), prefix, n) == 0;
        }

        std::wstring MakeLongPath(const std::wstring& path)
        {
            if (path.empty())
                return path;

            if (StartsWith(path, L"\\\\?\\"))
                return path;

            if (StartsWith(path, L"\\\\"))
            {
                // UNC: \\server\share\path -> \\?\UNC\server\share\path
                return L"\\\\?\\UNC" + path.substr(1);
            }

            if (path.size() >= 3 && path[1] == L':' && (path[2] == L'\\' || path[2] == L'/'))
                return L"\\\\?\\" + path;

            return path;
        }

        unsigned long long CombineHighLow(DWORD high, DWORD low)
        {
            return (static_cast<unsigned long long>(high) << 32) | static_cast<unsigned long long>(low);
        }

        unsigned long long RoundUp(unsigned long long value, unsigned long long unit)
        {
            if (unit == 0 || value == 0)
                return value;
            const unsigned long long remainder = value % unit;
            if (remainder == 0)
                return value;
            const unsigned long long add = unit - remainder;
            if (value > ULLONG_MAX - add)
                return value;
            return value + add;
        }

        unsigned long long GetLogicalSize(const WIN32_FIND_DATAW& fd)
        {
            return CombineHighLow(fd.nFileSizeHigh, fd.nFileSizeLow);
        }

        DWORD GetAttributesSafe(const std::wstring& path)
        {
            return GetFileAttributesW(MakeLongPath(path).c_str());
        }

        bool IsSparseCompressedOrCloud(DWORD attrs)
        {
            if (attrs == INVALID_FILE_ATTRIBUTES)
                return false;

            const DWORD flags = FILE_ATTRIBUTE_COMPRESSED |
                                FILE_ATTRIBUTE_SPARSE_FILE |
                                FILE_ATTRIBUTE_OFFLINE |
                                FILE_ATTRIBUTE_RECALL_ON_OPEN |
                                FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS |
                                FILE_ATTRIBUTE_UNPINNED;
            return (attrs & flags) != 0;
        }

        unsigned long long GetClusterSizeForPath(const std::wstring& path)
        {
            static std::mutex clusterSizeCacheMutex;
            static std::unordered_map<std::wstring, unsigned long long> clusterSizeCache;

            wchar_t root[MAX_PATH] = {};
            std::wstring pathForVolume = path;

            // GetVolumePathNameW is more reliable without \\?\ prefix for typical paths.
            if (StartsWith(pathForVolume, L"\\\\?\\UNC\\"))
                pathForVolume = L"\\" + pathForVolume.substr(7);
            else if (StartsWith(pathForVolume, L"\\\\?\\"))
                pathForVolume = pathForVolume.substr(4);

            if (!GetVolumePathNameW(pathForVolume.c_str(), root, ARRAYSIZE(root)))
                return 1;

            {
                std::lock_guard<std::mutex> lock(clusterSizeCacheMutex);
                auto it = clusterSizeCache.find(root);
                if (it != clusterSizeCache.end())
                    return it->second;
            }

            DWORD sectorsPerCluster = 0;
            DWORD bytesPerSector = 0;
            DWORD freeClusters = 0;
            DWORD totalClusters = 0;

            if (!GetDiskFreeSpaceW(root, &sectorsPerCluster, &bytesPerSector, &freeClusters, &totalClusters))
                return 1;

            const unsigned long long cluster = static_cast<unsigned long long>(sectorsPerCluster) *
                                               static_cast<unsigned long long>(bytesPerSector);
            const unsigned long long value = cluster == 0 ? 1 : cluster;

            {
                std::lock_guard<std::mutex> lock(clusterSizeCacheMutex);
                clusterSizeCache[root] = value;
            }

            return value;
        }

        SizeResult GetCompressedSize(const std::wstring& path)
        {
            SizeResult result;
            DWORD high = 0;
            SetLastError(ERROR_SUCCESS);
            const DWORD low = GetCompressedFileSizeW(MakeLongPath(path).c_str(), &high);
            const DWORD err = GetLastError();

            if (low == INVALID_FILE_SIZE && err != ERROR_SUCCESS)
            {
                result.ok = false;
                result.lastError = err;
                return result;
            }

            result.ok = true;
            result.bytes = CombineHighLow(high, low);
            result.lastError = ERROR_SUCCESS;
            return result;
        }

        SizeResult GetAllocatedSizeForFile(const std::wstring& path, unsigned long long logicalSize, DWORD attrs)
        {
            SizeResult result;
            result.ok = true;
            result.lastError = ERROR_SUCCESS;

            // For sparse/compressed/cloud-placeholder files GetCompressedFileSizeW is the important value.
            // For normal files Windows Explorer normally rounds to allocation units / clusters.
            if (IsSparseCompressedOrCloud(attrs))
            {
                return GetCompressedSize(path);
            }

            const unsigned long long cluster = GetClusterSizeForPath(path);
            result.bytes = RoundUp(logicalSize, cluster);
            return result;
        }

        bool ShouldSkipDirectoryReparsePoint(const WIN32_FIND_DATAW& fd)
        {
            if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0)
                return false;
            if ((fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0)
                return false;

            // Avoid infinite recursion through junctions/symlinks/mount-points.
            // Do NOT skip OneDrive/Cloud Files reparse tags; those still need to be enumerated.
            return fd.dwReserved0 == IO_REPARSE_TAG_SYMLINK || fd.dwReserved0 == IO_REPARSE_TAG_MOUNT_POINT;
        }

        SizeResult GetAllocatedSizeForDirectory(const std::wstring& directory, const volatile bool* abortFlag)
        {
            SizeResult total;
            total.ok = true;
            total.bytes = 0;
            total.lastError = ERROR_SUCCESS;

            if (IsAbortRequested(abortFlag))
            {
                total.ok = false;
                total.lastError = ERROR_CANCELLED;
                return total;
            }

            std::wstring pattern = directory;
            if (!pattern.empty() && pattern.back() != L'\\' && pattern.back() != L'/')
                pattern += L'\\';
            pattern += L'*';

            WIN32_FIND_DATAW fd = {};
            HANDLE hFind = FindFirstFileW(MakeLongPath(pattern).c_str(), &fd);
            if (hFind == INVALID_HANDLE_VALUE)
            {
                total.ok = false;
                total.lastError = GetLastError();
                return total;
            }

            do
            {
                if (IsAbortRequested(abortFlag))
                {
                    total.ok = false;
                    total.lastError = ERROR_CANCELLED;
                    break;
                }

                if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0)
                    continue;

                std::wstring child = directory;
                if (!child.empty() && child.back() != L'\\' && child.back() != L'/')
                    child += L'\\';
                child += fd.cFileName;

                if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
                {
                    if (ShouldSkipDirectoryReparsePoint(fd))
                        continue;

                    SizeResult sub = GetAllocatedSizeForDirectory(child, abortFlag);
                    if (!sub.ok && sub.lastError == ERROR_CANCELLED)
                    {
                        total.ok = false;
                        total.lastError = ERROR_CANCELLED;
                        break;
                    }

                    // Permission errors in a subfolder should not kill the whole column.
                    // We ignore inaccessible subfolders, same practical behavior as many disk analyzers.
                    if (sub.ok)
                        total.bytes += sub.bytes;
                }
                else
                {
                    SizeResult fileSize = GetAllocatedSizeForFile(child, GetLogicalSize(fd), fd.dwFileAttributes);
                    if (fileSize.ok)
                        total.bytes += fileSize.bytes;
                }
            }
            while (FindNextFileW(hFind, &fd));

            const DWORD endErr = GetLastError();
            FindClose(hFind);

            if (total.ok && endErr != ERROR_NO_MORE_FILES)
            {
                total.ok = false;
                total.lastError = endErr;
            }

            return total;
        }

        void AddPart(std::vector<std::wstring>& parts, const wchar_t* text)
        {
            if (text && *text)
                parts.emplace_back(text);
        }

        std::wstring JoinParts(const std::vector<std::wstring>& parts)
        {
            std::wstring out;
            for (size_t i = 0; i < parts.size(); ++i)
            {
                if (i > 0)
                    out += L", ";
                out += parts[i];
            }
            return out;
        }
    }

    SizeResult GetAllocatedSizeForPath(const std::wstring& path, bool isDirectory, const volatile bool* abortFlag)
    {
        if (path.empty())
        {
            return { false, 0, ERROR_INVALID_PARAMETER };
        }

        if (isDirectory)
            return GetAllocatedSizeForDirectory(path, abortFlag);

        WIN32_FILE_ATTRIBUTE_DATA attrData = {};
        if (!GetFileAttributesExW(MakeLongPath(path).c_str(), GetFileExInfoStandard, &attrData))
        {
            return { false, 0, GetLastError() };
        }

        const unsigned long long logicalSize = CombineHighLow(attrData.nFileSizeHigh, attrData.nFileSizeLow);
        return GetAllocatedSizeForFile(path, logicalSize, attrData.dwFileAttributes);
    }

    std::wstring FormatBytes(unsigned long long bytes)
    {
        const wchar_t* units[] = { L"B", L"KB", L"MB", L"GB", L"TB", L"PB" };
        double value = static_cast<double>(bytes);
        size_t unitIndex = 0;

        while (value >= 1024.0 && unitIndex < ARRAYSIZE(units) - 1)
        {
            value /= 1024.0;
            ++unitIndex;
        }

        wchar_t buffer[64] = {};
        if (unitIndex == 0)
            StringCchPrintfW(buffer, ARRAYSIZE(buffer), L"%llu %s", bytes, units[unitIndex]);
        else if (value >= 100.0)
            StringCchPrintfW(buffer, ARRAYSIZE(buffer), L"%.0f %s", value, units[unitIndex]);
        else if (value >= 10.0)
            StringCchPrintfW(buffer, ARRAYSIZE(buffer), L"%.1f %s", value, units[unitIndex]);
        else
            StringCchPrintfW(buffer, ARRAYSIZE(buffer), L"%.2f %s", value, units[unitIndex]);

        return buffer;
    }

    std::wstring GetCloudStatusText(const std::wstring& path, const MCNS::IFileItem* fileItem)
    {
        std::vector<std::wstring> parts;

        DWORD attrs = GetAttributesSafe(path);
        if (attrs == INVALID_FILE_ATTRIBUTES)
            return L"UNKNOWN";

        if (fileItem)
        {
            if (fileItem->IsOnlineOnly())
                AddPart(parts, L"ONLINE_ONLY");
            if (fileItem->IsLocalAvailable())
                AddPart(parts, L"LOCAL_AVAILABLE");
            if (fileItem->IsAlwaysAvailable())
                AddPart(parts, L"ALWAYS_LOCAL");
            if (fileItem->IsOnDemandItem())
                AddPart(parts, L"ON_DEMAND");
        }

        if ((attrs & FILE_ATTRIBUTE_OFFLINE) != 0)
            AddPart(parts, L"OFFLINE");
        if ((attrs & FILE_ATTRIBUTE_UNPINNED) != 0)
            AddPart(parts, L"UNPINNED");
        if ((attrs & FILE_ATTRIBUTE_PINNED) != 0)
            AddPart(parts, L"PINNED");
        if ((attrs & FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS) != 0)
            AddPart(parts, L"RECALL_ON_DATA_ACCESS");
        if ((attrs & FILE_ATTRIBUTE_RECALL_ON_OPEN) != 0)
            AddPart(parts, L"RECALL_ON_OPEN");
        if ((attrs & FILE_ATTRIBUTE_SPARSE_FILE) != 0)
            AddPart(parts, L"SPARSE");
        if ((attrs & FILE_ATTRIBUTE_COMPRESSED) != 0)
            AddPart(parts, L"COMPRESSED");
        if ((attrs & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
            AddPart(parts, L"REPARSE_POINT");

        if (parts.empty())
            return L"LOCAL";

        return JoinParts(parts);
    }
}
