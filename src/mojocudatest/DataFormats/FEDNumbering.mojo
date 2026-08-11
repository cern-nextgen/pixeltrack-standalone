struct FEDNumbering:
    alias _in: List[Bool] = initIn()

    alias NOT_A_FEDID = -1
    alias MAXFEDID = 4096  # must be larger than largest used FED id
    alias MINSiPixelFEDID = 0
    alias MAXSiPixelFEDID = 40  # increase from 39 for the pilot blade fed
    alias MINSiStripFEDID = 50
    alias MAXSiStripFEDID = 489
    alias MINPreShowerFEDID = 520
    alias MAXPreShowerFEDID = 575
    alias MINTotemTriggerFEDID = 577
    alias MAXTotemTriggerFEDID = 577
    alias MINTotemRPHorizontalFEDID = 578
    alias MAXTotemRPHorizontalFEDID = 581
    alias MINCTPPSDiamondFEDID = 582
    alias MAXCTPPSDiamondFEDID = 583
    alias MINTotemRPVerticalFEDID = 584
    alias MAXTotemRPVerticalFEDID = 585
    alias MINTotemRPTimingVerticalFEDID = 586
    alias MAXTotemRPTimingVerticalFEDID = 587
    alias MINECALFEDID = 600
    alias MAXECALFEDID = 670
    alias MINCASTORFEDID = 690
    alias MAXCASTORFEDID = 693
    alias MINHCALFEDID = 700
    alias MAXHCALFEDID = 731
    alias MINLUMISCALERSFEDID = 735
    alias MAXLUMISCALERSFEDID = 735
    alias MINCSCFEDID = 750
    alias MAXCSCFEDID = 757
    alias MINCSCTFFEDID = 760
    alias MAXCSCTFFEDID = 760
    alias MINDTFEDID = 770
    alias MAXDTFEDID = 779
    alias MINDTTFFEDID = 780
    alias MAXDTTFFEDID = 780
    alias MINRPCFEDID = 790
    alias MAXRPCFEDID = 795
    alias MINTriggerGTPFEDID = 812
    alias MAXTriggerGTPFEDID = 813
    alias MINTriggerEGTPFEDID = 814
    alias MAXTriggerEGTPFEDID = 814
    alias MINTriggerGCTFEDID = 745
    alias MAXTriggerGCTFEDID = 749
    alias MINTriggerLTCFEDID = 816
    alias MAXTriggerLTCFEDID = 824
    alias MINTriggerLTCmtccFEDID = 815
    alias MAXTriggerLTCmtccFEDID = 815
    alias MINTriggerLTCTriggerFEDID = 816
    alias MAXTriggerLTCTriggerFEDID = 816
    alias MINTriggerLTCHCALFEDID = 817
    alias MAXTriggerLTCHCALFEDID = 817
    alias MINTriggerLTCSiStripFEDID = 818
    alias MAXTriggerLTCSiStripFEDID = 818
    alias MINTriggerLTCECALFEDID = 819
    alias MAXTriggerLTCECALFEDID = 819
    alias MINTriggerLTCTotemCastorFEDID = 820
    alias MAXTriggerLTCTotemCastorFEDID = 820
    alias MINTriggerLTCRPCFEDID = 821
    alias MAXTriggerLTCRPCFEDID = 821
    alias MINTriggerLTCCSCFEDID = 822
    alias MAXTriggerLTCCSCFEDID = 822
    alias MINTriggerLTCDTFEDID = 823
    alias MAXTriggerLTCDTFEDID = 823
    alias MINTriggerLTCSiPixelFEDID = 824
    alias MAXTriggerLTCSiPixelFEDID = 824
    alias MINCSCDDUFEDID = 830
    alias MAXCSCDDUFEDID = 869
    alias MINCSCContingencyFEDID = 880
    alias MAXCSCContingencyFEDID = 887
    alias MINCSCTFSPFEDID = 890
    alias MAXCSCTFSPFEDID = 901
    alias MINDAQeFEDFEDID = 902
    alias MAXDAQeFEDFEDID = 931
    alias MINMetaDataSoftFEDID = 1022
    alias MAXMetaDataSoftFEDID = 1022
    alias MINDAQmFEDFEDID = 1023
    alias MAXDAQmFEDFEDID = 1023
    alias MINTCDSuTCAFEDID = 1024
    alias MAXTCDSuTCAFEDID = 1099
    alias MINHCALuTCAFEDID = 1100
    alias MAXHCALuTCAFEDID = 1199
    alias MINSiPixeluTCAFEDID = 1200
    alias MAXSiPixeluTCAFEDID = 1349
    alias MINRCTFEDID = 1350
    alias MAXRCTFEDID = 1359
    alias MINCalTrigUp = 1360
    alias MAXCalTrigUp = 1367
    alias MINDTUROSFEDID = 1369
    alias MAXDTUROSFEDID = 1371
    alias MINTriggerUpgradeFEDID = 1372
    alias MAXTriggerUpgradeFEDID = 1409
    alias MINSiPixel2nduTCAFEDID = 1500
    alias MAXSiPixel2nduTCAFEDID = 1649
    alias MINSiPixelTestFEDID = 1450
    alias MAXSiPixelTestFEDID = 1461
    alias MINSiPixelAMC13FEDID = 1410
    alias MAXSiPixelAMC13FEDID = 1449
    alias MINCTPPSPixelsFEDID = 1462
    alias MAXCTPPSPixelsFEDID = 1466
    alias MINGEMFEDID = 1467
    alias MAXGEMFEDID = 1472
    alias MINME0FEDID = 1473
    alias MAXME0FEDID = 1478
    alias MINDAQvFEDFEDID = 2815
    alias MAXDAQvFEDFEDID = 4095

    @staticmethod
    @always_inline
    fn lastFEDId() -> Int:
        return FEDNumbering.MAXFEDID

    @staticmethod
    @always_inline
    fn inRange(var i: Int) -> Bool:
        return FEDNumbering._in[i]

    @staticmethod
    @always_inline
    fn inRangeNoGT(var i: Int) -> Bool:
        if (
            i >= FEDNumbering.MINTriggerGTPFEDID
            and i <= FEDNumbering.MAXTriggerGTPFEDID
        ) or (
            i >= FEDNumbering.MINTriggerEGTPFEDID
            and i <= FEDNumbering.MAXTriggerEGTPFEDID
        ):
            return False
        return FEDNumbering._in[i]


fn initIn() -> List[Bool]:
    var _in: List[Bool] = List[Bool](
        length=FEDNumbering.MAXFEDID + 1, fill=False
    )

    @parameter
    for i in range(
        FEDNumbering.MINSiPixelFEDID, FEDNumbering.MAXSiPixelFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINSiStripFEDID, FEDNumbering.MAXSiStripFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINPreShowerFEDID, FEDNumbering.MAXPreShowerFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(FEDNumbering.MINECALFEDID, FEDNumbering.MAXECALFEDID + 1):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINCASTORFEDID, FEDNumbering.MAXCASTORFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(FEDNumbering.MINHCALFEDID, FEDNumbering.MAXHCALFEDID + 1):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINLUMISCALERSFEDID, FEDNumbering.MAXLUMISCALERSFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(FEDNumbering.MINCSCFEDID, FEDNumbering.MAXCSCFEDID + 1):
        _in[i] = True

    @parameter
    for i in range(FEDNumbering.MINCSCTFFEDID, FEDNumbering.MAXCSCTFFEDID + 1):
        _in[i] = True

    @parameter
    for i in range(FEDNumbering.MINDTFEDID, FEDNumbering.MAXDTFEDID + 1):
        _in[i] = True

    @parameter
    for i in range(FEDNumbering.MINDTTFFEDID, FEDNumbering.MAXDTTFFEDID + 1):
        _in[i] = True

    @parameter
    for i in range(FEDNumbering.MINRPCFEDID, FEDNumbering.MAXRPCFEDID + 1):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINTriggerGTPFEDID, FEDNumbering.MAXTriggerGTPFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINTriggerEGTPFEDID, FEDNumbering.MAXTriggerEGTPFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINTriggerGCTFEDID, FEDNumbering.MAXTriggerGCTFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINTriggerLTCFEDID, FEDNumbering.MAXTriggerLTCFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINTriggerLTCmtccFEDID,
        FEDNumbering.MAXTriggerLTCmtccFEDID + 1,
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINCSCDDUFEDID, FEDNumbering.MAXCSCDDUFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINCSCContingencyFEDID,
        FEDNumbering.MAXCSCContingencyFEDID + 1,
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINCSCTFSPFEDID, FEDNumbering.MAXCSCTFSPFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINDAQeFEDFEDID, FEDNumbering.MAXDAQeFEDFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINDAQmFEDFEDID, FEDNumbering.MAXDAQmFEDFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINTCDSuTCAFEDID, FEDNumbering.MAXTCDSuTCAFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINHCALuTCAFEDID, FEDNumbering.MAXHCALuTCAFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINSiPixeluTCAFEDID, FEDNumbering.MAXSiPixeluTCAFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINDTUROSFEDID, FEDNumbering.MAXDTUROSFEDID + 1
    ):
        _in[i] = True

    @parameter
    for i in range(
        FEDNumbering.MINTriggerUpgradeFEDID,
        FEDNumbering.MAXTriggerUpgradeFEDID + 1,
    ):
        _in[i] = True

    return _in^
