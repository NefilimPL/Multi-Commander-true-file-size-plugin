#pragma once
#include "stdafx.h"

MCNSBEGIN

class MCRealDiskSizeProp final : public IFileProperties
{
public:
    MCRealDiskSizeProp() = default;
    ~MCRealDiskSizeProp() override = default;

    static bool GetExtensionInfo(DLLExtensionInfo* pInfo);

    char* Get_ModuleID() override;
    long PreStartInit(IMultiAppInterface* pAppInterface) override;

    bool Open(IFileItem* pParentFileItem) override;
    bool Open(const WCHAR* szParentPath) override;
    bool Close() override;

    bool GetDisplayValue(IFileItem* pFileItem, WCHAR* propData, WORD nLen, WORD PropertyId, const volatile bool* pAbort) override;
    bool GetPropStr(IFileItem* pFileItem, WCHAR* propData, WORD nLen, WORD PropertyId, const volatile bool* pAbort) override;
    bool GetPropNum(IFileItem* pFileItem, INT64* propData, WORD PropertyId, const volatile bool* pAbort) override;
    bool GetPropDouble(IFileItem* pFileItem, double* propData, WORD PropertyId, const volatile bool* pAbort) override;
    bool FormatDisplayValue(WCHAR* szDisplayValue, WORD nLen, INT64 nValue, WORD PropertyId) override;
    bool SetProp(IFileItem* pFileItem, WORD PropertyId, const BYTE* propData) override;
    bool Execute(ExecuteInfo* pExecuteInfo) override;

    // MC 15.8 calls two tail IFileProperties vtable slots that are not present
    // in the public 2.4 SDK. Keep no-op entries so refresh cannot call past
    // the end of this class' vtable while the plugin reports interface 2.5.
    virtual bool ReservedForMultiCommander25VTable0(IFileItem* pFileItem);
    virtual bool ReservedForMultiCommander25VTable1(IFileItem* pFileItem);

private:
    static char m_GuidString[34];
};

MCNSEND
