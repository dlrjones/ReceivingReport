
-- ================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Rob Jones
-- Create date: 2/7/2013
-- Description:	a modified form of up_rpt_receipt, the mod was to change the ORDER BY
--				clause of the final output. This procedure is called from an app 
--				(ReceivingReport.exe) which exports the output to an excel file
--				SAMPLE from the McKesson report - up_rpt_receipt
--				up_rpt_receipt;1 '(1000)', '2013-02-07 00:00:00.000', '2013-02-07 23:59:29.000', 'Y', '', '', 'N', '', '', '', '', '', '', '', '', 0
-- =============================================
CREATE PROCEDURE [dbo].ReceiveReport(
			   @p_corp_id varchar(max),  ----mandatory
			   @p_rcv_beg_date varchar(255),  --mandatory
			   @p_rcv_end_date varchar(255), --mandatory
			   @p_group_by_loc varchar(5),  --pcr 36302 --mandatory default to Yes
			   @p_sub_acct_id varchar(max), --pcr 36302
			   @p_po_sub_line_cc_id varchar(max),
			   @p_page_break varchar(5),
			   @p_po_id varchar(max),
			   @p_delv_loc_id varchar(max),
 			   @p_item_id varchar(max),
			   @p_vend_id varchar(max),
			   @p_project_id varchar(max),
			   @p_sub_project_id varchar(max),
			   @p_sub_ledger_rule varchar(max),
			   @p_sub_ledger_val varchar(max),
			   @i_dbid int
)
as
begin
set nocount on

Declare
 @string  varchar(max), --extract parameter string
 @string1 varchar(max),
 @string2 varchar(max),
 @string3 varchar(max),
 @string4 varchar(max),
 @c_DB_ID int,
 @c_DB_ID_char char(6)

--****************************************************
--#RCVRPT temp table Notes:
--These fields are returned for testing/troubleshooting purposes only: PO_LINE_NO,RCVD_PRICE,ALLOC_DOLLAR_AMT,ALLOC_PERCENT_NBR
--ALLOC_SEQ_NO is needed to update $Tax for allocation rows and used in final order by clause
--COMP_SEQ_NO used in final order by clause

   create table #RCVRPT
   (	PO_ID int null,
	PO_IDB int null,
	PO_LINE_ID int null,
	PO_LINE_IDB int null,
 	PO_PO_NO char(22) null,
	PO_LINE_NO smallint null,
	PO_LINE_QTY float null,
	RCV_RCV_DATE datetime null,
	RCV_PO_SUB_LINE_QTY  float null,
	RCV_PO_SUB_LINE_UM_CD char(16) null,
	PO_LINE_PRICE float null,
	RCVD_PRICE float null,
	ALLOC_DOLLAR_AMT float null,
	ALLOC_PERCENT_NBR float null,
	PO_LINE_UM_CD char(16) null,
	RCV_PO_SUB_LINE_ALT_QTY  float null,
	RCV_PO_SUB_LINE_ALT_UM_CD char(16) null,
	CORP_ACCT_NO char(40) null,
	CORP_NAME char(40) null,
	CC_ACCT_NO char(40) null,
	CC_NAME char(40) null,
	EXP_CODE_ACCT_NO char(40) null,
	EXP_CODE_NAME char(40) null,
	SUB_ACCT_ACCT_NO char(40) null,
	SUB_ACCT_NAME char(40) null,
	ITEM_ITEM_NO char(15) null,
	ITEM_DESC char(255) null,
	VENDOR_NAME char(40) null,
	DELV_LOC_NAME char(40) null,
	ITEM_CTLG_ITEM_IND char(1) null,
	RCV_NAME char(40) null,
	is_delv_loc_supp_loc char(1) null,
	po_line_tax money null,
	CODE_TABLE_NAME char(40) null,
	SubLedValue char(30) null,
	SUB_PROJ_CODE char(15) null,
	PROJ_CODE char(15) null,
	LINE_ALLOC_IND char(1) null,
	ALLOC_SEQ_NO smallint null,
	COMP_SEQ_NO smallint null,
	ITEM_COMP_IND char(1) null,
	RCV_COMP_IND char(1) null,
	NON_CTLG_ALT_UM_FLAG smallint null -- PCR 44420
)


CREATE TABLE #SUBLEDGE_RULE (
	SUB_LEDGER_RULE_ID  	INT NULL,
	SUB_LEDGER_RULE_IDB  	INT NULL,
	AcctSubLdgRl 		CHAR(8) NULL
 )


If @i_dbid = 0
    Begin 
	SET ROWCOUNT 1

	Select @c_DB_ID = DB_ID
	from DB_ID
        where DB_ID is not null and
        DB_ID <> 0

       SET ROWCOUNT 0
    End

Else

    SELECT @c_DB_ID = @i_dbid

Select @c_DB_ID_char = convert(char(6),@c_DB_ID)

/******************* insert into #SUBLEDGE_RULE *******************************************/

if @p_sub_ledger_rule <> '' and @p_sub_ledger_rule is not null
Select @string = '
	INSERT INTO #SUBLEDGE_RULE
    Select 
    	SUB_LEDGER_RULE.SUB_LEDGER_RULE_ID, 
    	SUB_LEDGER_RULE.SUB_LEDGER_RULE_IDB,  
    	SUB_LEDGER_RULE.AcctSubLdgRl
	from  SUB_LEDGER_RULE
    where SUB_LEDGER_RULE.AcctSubLdgRl in '+ @p_sub_ledger_rule  -- ('DEBT','PATIENT','PROJECT','RANGE')*/

exec(@string)

--print @string
--SELECT * FROM #SUBLEDGE_RULE

-----------------------------------------------------------------------------------------------------------------------------------

-- Query 1 of 4 
-- this query returns 'regular' receipt lines for stock and non-catalog items and 
-- receipts for parent po lines that have components, but have been received by parent po line.
Select @string1 = '
   insert into #RCVRPT

  SELECT	PO.PO_ID,
		PO.PO_IDB,
		PO_LINE.PO_LINE_ID,
		PO_LINE.PO_LINE_IDB,
		PO.PO_NO,
		PO_LINE.LINE_NO,  --used for testing/troubleshooting purposes only
		PO_LINE.QTY,
		RCV.RCV_DATE,
		RCV_PO_SUB_LINE.QTY,
		RCV_PO_SUB_LINE.UM_CD,
		PO_LINE.PRICE,
		(RCV_PO_SUB_LINE.QTY * PO_LINE.PRICE), --Recieved Extended Cost
		0, --ALLOC DOLLAR AMT used for testing/troubleshooting purposes only
		0, --PO_LINE_ALLOC.PERCENT_NBR used for testing/troubleshooting purposes only
                PO_LINE.UM_CD,
		RCV_PO_SUB_LINE.ALT_QTY,
		RCV_PO_SUB_LINE.ALT_UM_CD,
		CORP.ACCT_NO, --po line corporation
		CORP.NAME, 
		CC.ACCT_NO, --This is the po_line Cost Center 
		CC.NAME, 
		EXP_CODE.ACCT_NO,  --po_line
		EXP_CODE.NAME,  
		SUB_ACCT.ACCT_NO,  --po_line
		SUB_ACCT.NAME, 
		Case when ITEM.COMPONENT_IND = ''P''  --PO lines that have components and are received by parent line display the word [Component]
            	then ''[Component]''
		when ITEM.CTLG_ITEM_IND = ''N'' 
		then ''[Non-catalog]''
             	else ITEM.ITEM_NO end,
		ITEM.DESCR,  --This is the PO Line item description
		VEND.NAME,
		LOC.NAME,  --This is the Delivery Location
		case when ITEM.CTLG_ITEM_IND = '''' then ''N''  --must account for null and blanks untill pcr 34918 is fixed
		     when ITEM.CTLG_ITEM_IND is null then ''N''
		     else ITEM.CTLG_ITEM_IND end,
		USR.NAME, --RCV NAME
		Case when LOC.LOC_TYPE = ''2''
            	then ''Y'' else ''N'' end,
		0, --PO_LINE_TAX
		CODE_TABLE.NAME, 
		SUB_LEDGER.SubLedValue, --po_line
		SUB_PROJECT.SUB_PROJ_CODE, --po_line
		PROJECT.PROJ_CODE, --po_line
		ISNULL(PO_LINE.LINE_ALLOC_IND,''N''), 
		0, --PO_LINE_ALLOC_SEQ_NO 
		0, --PO_LINE_COMPONENT_SEQ_NO used for testing/troubleshooting purposes and order by clause
		case when ITEM.COMPONENT_IND is null then ''N''
	     	when ITEM.COMPONENT_IND = '''' then ''N''  --this is adressed in pcr 34918
	     	else ITEM.COMPONENT_IND end,
		ISNULL(PO_SUB_LINE.RCV_COMP_IND, ''N''), --should always be N in this query
		0 -- PCR 44420 sets NON_CTLG_ALT_UM_FLAG 
	
FROM 	RCV
JOIN RCV_PO_SUB_LINE ON
	(RCV.RCV_ID  = RCV_PO_SUB_LINE.RCV_ID and
	 RCV.RCV_IDB = RCV_PO_SUB_LINE.RCV_IDB)

JOIN PO_SUB_LINE ON
	(RCV_PO_SUB_LINE.PO_SUB_LINE_ID  = PO_SUB_LINE.PO_SUB_LINE_ID and
	 RCV_PO_SUB_LINE.PO_SUB_LINE_IDB = PO_SUB_LINE.PO_SUB_LINE_IDB and
	(PO_SUB_LINE.RCV_COMP_IND = ''N'' OR PO_SUB_LINE.RCV_COMP_IND IS NULL))

JOIN PO_LINE ON
	(PO_SUB_LINE.PO_LINE_ID  = PO_LINE.PO_LINE_ID and
	 PO_SUB_LINE.PO_LINE_IDB = PO_LINE.PO_LINE_IDB)

JOIN PO ON
	(PO_LINE.PO_ID  = PO.PO_ID and
	 PO_LINE.PO_IDB = PO.PO_IDB and
	(PO_LINE.LINE_ALLOC_IND = ''N'' OR PO_LINE.LINE_ALLOC_IND IS NULL))

LEFT JOIN CODE_TABLE ON
	(RCV_PO_SUB_LINE.REASON_CD = CODE_TABLE.TYPE_CD)

JOIN USR ON
	(RCV.REC_CREATE_USR_ID  = USR.USR_ID and
	 RCV.REC_CREATE_USR_IDB = USR.USR_IDB)

JOIN VEND ON
	(PO.VEND_ID  = VEND.VEND_ID and
	 PO.VEND_IDB = VEND.VEND_IDB)

JOIN LOC ON
	(PO_SUB_LINE.DELV_LOC_ID  = LOC.LOC_ID and
	 PO_SUB_LINE.DELV_LOC_IDB = LOC.LOC_IDB)

JOIN SUB_ACCT ON
	(SUB_ACCT.SUB_ACCT_ID  = PO_LINE.SUB_ACCT_ID and
	 SUB_ACCT.SUB_ACCT_IDB = PO_LINE.SUB_ACCT_IDB)

JOIN EXP_CODE ON
	(SUB_ACCT.EXP_CODE_ID  = EXP_CODE.EXP_CODE_ID and
	 SUB_ACCT.EXP_CODE_IDB = EXP_CODE.EXP_CODE_IDB)

JOIN CC ON
	(EXP_CODE.CC_ID  = CC.CC_ID and
	 EXP_CODE.CC_IDB = CC.CC_IDB)

JOIN CORP ON
	(CC.CORP_ID  = CORP.CORP_ID and
	 CC.CORP_IDB = CORP.CORP_IDB)

JOIN ITEM ON
	(PO_LINE.ITEM_ID  = ITEM.ITEM_ID and
	 PO_LINE.ITEM_IDB = ITEM.ITEM_IDB and
	 ITEM.IMPORT_STATUS = 0)

JOIN SUB_PROJECT ON
	(PO_LINE.SUB_PROJECT_ID  = SUB_PROJECT.SUB_PROJECT_ID and
	 PO_LINE.SUB_PROJECT_IDB = SUB_PROJECT.SUB_PROJECT_IDB)

JOIN PROJECT ON
	(SUB_PROJECT.PROJECT_ID  = PROJECT.PROJECT_ID and
	 SUB_PROJECT.PROJECT_IDB = PROJECT.PROJECT_IDB)

LEFT JOIN SUB_LEDGER ON
	(PO_LINE.SUB_LEDGER_ID  = SUB_LEDGER.SUB_LEDGER_ID and
	 PO_LINE.SUB_LEDGER_IDB = SUB_LEDGER.SUB_LEDGER_IDB and 
	 SUB_LEDGER.CORP_ID = CC.CORP_ID and 
	 SUB_LEDGER.CORP_IDB = CC.CORP_IDB ) '

-- Query 2 of 4 
-- this query returns receipt lines for stock and non-catalog items that have allocations and 
-- receipts for parent po lines that have components AND have allocations, but have been received by parent po line.
Select @string2 = '
union 
SELECT		PO.PO_ID,
		PO.PO_IDB,
		PO_LINE.PO_LINE_ID,
		PO_LINE.PO_LINE_IDB,
		PO.PO_NO,
		PO_LINE.LINE_NO,  --used for testing/troubleshooting purposes only
		PO_LINE.QTY,
		RCV.RCV_DATE,
		RCV_PO_SUB_LINE.QTY,
		RCV_PO_SUB_LINE.UM_CD,
		(PO_LINE.PRICE * (PO_LINE_ALLOC.PERCENT_NBR * .01)),
		((PO_LINE.PRICE * RCV_PO_SUB_LINE.QTY ) * (PO_LINE_ALLOC.PERCENT_NBR * .01)), --used for testing/troubleshooting purposes only
		PO_LINE_ALLOC.DOLLAR_AMT, --used for testing/troubleshooting purposes only
		PO_LINE_ALLOC.PERCENT_NBR, --used for testing/troubleshooting purposes only
                PO_LINE.UM_CD,
		RCV_PO_SUB_LINE.ALT_QTY,
		RCV_PO_SUB_LINE.ALT_UM_CD,
		CORP.ACCT_NO, --po_line_allocation Corporation
		CORP.NAME,
		CC.ACCT_NO, --po_line_allocation cc info
		CC.NAME,
		EXP_CODE.ACCT_NO, --po_line_allocation exp code info
		EXP_CODE.NAME,
		SUB_ACCT.ACCT_NO, --po_line_allocation sub_acct info
		SUB_ACCT.NAME,
		CASE WHEN ITEM.COMPONENT_IND = ''P''
		THEN ''[Component]''
		when ITEM.CTLG_ITEM_IND = ''N'' 
		then ''[Non-catalog]''
		else ITEM.ITEM_NO end, --po_line item
		ITEM.DESCR,
		VEND.NAME,
		LOC.NAME,
		case when ITEM.CTLG_ITEM_IND = '''' then ''N''
		     when ITEM.CTLG_ITEM_IND is null then ''N''
		     else ITEM.CTLG_ITEM_IND end,
		USR.NAME, --RCV NAME
                Case when LOC.LOC_TYPE = ''2''
            	then ''Y''
             	else ''N''
             	end,
		0, --PO_LINE_TAX  
		CODE_TABLE.NAME,
		SUB_LEDGER.SubLedValue, --po_line_alloc data
		SUB_PROJECT.SUB_PROJ_CODE, --po_line_alloc data
		PROJECT.PROJ_CODE, --po_line_alloc data
		ISNULL(PO_LINE.LINE_ALLOC_IND,''N''),  
		PO_LINE_ALLOC.SEQ_NO, --used for testing/troubleshooting purposes and order by clause
		0, --PO_LINE_COMPONENT.SEQ_NO,
		case when ITEM.COMPONENT_IND is null then ''N''
	     	when ITEM.COMPONENT_IND = '''' then ''N''  --this is adressed in pcr 34918
	     	else ITEM.COMPONENT_IND end,
		ISNULL(PO_SUB_LINE.RCV_COMP_IND, ''N''),
		0 -- PCR 44420 sets NON_CTLG_ALT_UM_FLAG 

FROM RCV
JOIN RCV_PO_SUB_LINE ON
	(RCV.RCV_ID  = RCV_PO_SUB_LINE.RCV_ID and
	 RCV.RCV_IDB = RCV_PO_SUB_LINE.RCV_IDB)

JOIN PO_SUB_LINE ON
	(RCV_PO_SUB_LINE.PO_SUB_LINE_ID  = PO_SUB_LINE.PO_SUB_LINE_ID and
	 RCV_PO_SUB_LINE.PO_SUB_LINE_IDB = PO_SUB_LINE.PO_SUB_LINE_IDB and
	(PO_SUB_LINE.RCV_COMP_IND = ''N'' OR PO_SUB_LINE.RCV_COMP_IND IS NULL))

JOIN PO_LINE ON
	(PO_SUB_LINE.PO_LINE_ID  = PO_LINE.PO_LINE_ID and
	 PO_SUB_LINE.PO_LINE_IDB = PO_LINE.PO_LINE_IDB)

JOIN PO_LINE_ALLOC ON
	(PO_LINE.PO_LINE_ID  = PO_LINE_ALLOC.PO_LINE_ID and
	 PO_LINE.PO_LINE_IDB = PO_LINE_ALLOC.PO_LINE_IDB and
	 PO_LINE.LINE_ALLOC_IND = ''Y'')

JOIN PO ON 
	(PO_LINE.PO_ID  = PO.PO_ID and
	 PO_LINE.PO_IDB = PO.PO_IDB)

LEFT JOIN CODE_TABLE ON 
	(RCV_PO_SUB_LINE.REASON_CD = CODE_TABLE.TYPE_CD)

JOIN USR ON 
	(RCV.REC_CREATE_USR_ID  = USR.USR_ID and
	 RCV.REC_CREATE_USR_IDB = USR.USR_IDB)

JOIN VEND ON 
	(PO.VEND_ID  = VEND.VEND_ID and
	 PO.VEND_IDB = VEND.VEND_IDB)

JOIN LOC ON 
	(PO_SUB_LINE.DELV_LOC_ID  = LOC.LOC_ID and
	 PO_SUB_LINE.DELV_LOC_IDB = LOC.LOC_IDB)

JOIN SUB_ACCT ON 
	(SUB_ACCT.SUB_ACCT_ID  = PO_LINE_ALLOC.SUB_ACCT_ID and
	 SUB_ACCT.SUB_ACCT_IDB = PO_LINE_ALLOC.SUB_ACCT_IDB)

JOIN EXP_CODE ON
	(SUB_ACCT.EXP_CODE_ID  = EXP_CODE.EXP_CODE_ID and
	 SUB_ACCT.EXP_CODE_IDB = EXP_CODE.EXP_CODE_IDB)

JOIN CC ON
	(EXP_CODE.CC_ID  = CC.CC_ID and
	 EXP_CODE.CC_IDB = CC.CC_IDB)

JOIN CORP ON
	(CC.CORP_ID  = CORP.CORP_ID and
	 CC.CORP_IDB = CORP.CORP_IDB)

JOIN ITEM ON
	(PO_LINE.ITEM_ID  = ITEM.ITEM_ID and
	 PO_LINE.ITEM_IDB = ITEM.ITEM_IDB and
	 ITEM.IMPORT_STATUS = 0 )

JOIN SUB_PROJECT ON
	(PO_LINE_ALLOC.SUB_PROJECT_ID  = SUB_PROJECT.SUB_PROJECT_ID and
	 PO_LINE_ALLOC.SUB_PROJECT_IDB = SUB_PROJECT.SUB_PROJECT_IDB)

JOIN PROJECT ON
	(SUB_PROJECT.PROJECT_ID  = PROJECT.PROJECT_ID and
	 SUB_PROJECT.PROJECT_IDB = PROJECT.PROJECT_IDB)

LEFT JOIN SUB_LEDGER ON
	(PO_LINE.SUB_LEDGER_ID  = SUB_LEDGER.SUB_LEDGER_ID and
	 PO_LINE.SUB_LEDGER_IDB = SUB_LEDGER.SUB_LEDGER_IDB and
	 SUB_LEDGER.CORP_ID = CC.CORP_ID and 
	 SUB_LEDGER.CORP_IDB = CC.CORP_IDB ) '

-- Query 3 of 4 
-- returns receipt lines for items received by component
Select @string3 = '
union
 	 SELECT	PO.PO_ID,
		PO.PO_IDB,
		PO_LINE.PO_LINE_ID,
		PO_LINE.PO_LINE_IDB,
		PO.PO_NO,
		PO_LINE.LINE_NO, --used for testing/troubleshooting purposes only
		PO_LINE_COMPONENT.QTY * PO_LINE.QTY, --Extended Order Qty for Components.  Multiply POL qty by POLC qty for the component qty to be received
		RCV.RCV_DATE,
		RCV_PO_SUB_LINE_COMPONENT.QTY, --Rcvd component Qty, same as order um
		RCV_PO_SUB_LINE_COMPONENT.UM_CD,  --Rcvd component um
		PO_LINE_COMPONENT.PRICE, --component order price
		(PO_LINE_COMPONENT.PRICE * RCV_PO_SUB_LINE_COMPONENT.QTY), --rcvd extended cost used for testing/troubleshooting purposes
		0, --ALLOC_DOLLAR AMT
		0, --PO_LINE_ALLOC.PERCENT_NBR
                PO_LINE_COMPONENT.UM_CD, --Rcvd component Qty, same as rcvd um
		NULL, --COMPONENTS CANNOT BE RCVD IN ALT UM
		NULL, --COMPONENTS CANNOT BE RCVD IN ALT UM
		CORP.ACCT_NO, --po line corp info
		CORP.NAME, 
		CC.ACCT_NO, --po line cc info
		CC.NAME,
		EXP_CODE.ACCT_NO, --po line exp info
		EXP_CODE.NAME,
		SUB_ACCT.ACCT_NO, --po line sub info
		SUB_ACCT.NAME,
		''[Component]'', --item no
		ITEM.DESCR, --po line component desc
		VEND.NAME,
		LOC.NAME,
		''N'', --ITEM.CTLG_ITEM_IND
		USR.NAME,
		Case when LOC.LOC_TYPE = ''2''
            	then ''Y'' else ''N'' end,
		0, --PO_LINE_TAX
		CODE_TABLE.NAME, --component
		SUB_LEDGER.SubLedValue, --po line data
		SUB_PROJECT.SUB_PROJ_CODE, --po line data
		PROJECT.PROJ_CODE, --po line data
		ISNULL(PO_LINE.LINE_ALLOC_IND,''N''), --should always be N in this query
		0, --PO_LINE_ALLOC.SEQ_NO
		PO_LINE_COMPONENT.SEQ_NO, --used for testing/troubleshooting purposes and order by clause
		case when ITEM.COMPONENT_IND is null then ''N''
	     	when ITEM.COMPONENT_IND = '''' then ''N''  --this is adressed in pcr 34918 and should always be Y in this query
	     	else ITEM.COMPONENT_IND end,
		ISNULL(PO_SUB_LINE.RCV_COMP_IND, ''N''), --this should always be Y in this query
		0 -- PCR 44420 sets NON_CTLG_ALT_UM_FLAG 
FROM 	RCV
JOIN RCV_PO_SUB_LINE ON
	(RCV.RCV_ID  = RCV_PO_SUB_LINE.RCV_ID and
	 RCV.RCV_IDB = RCV_PO_SUB_LINE.RCV_IDB)

JOIN PO_SUB_LINE ON
	(RCV_PO_SUB_LINE.PO_SUB_LINE_ID  = PO_SUB_LINE.PO_SUB_LINE_ID and
	 RCV_PO_SUB_LINE.PO_SUB_LINE_IDB = PO_SUB_LINE.PO_SUB_LINE_IDB and
	 PO_SUB_LINE.RCV_COMP_IND = ''Y'' )

JOIN RCV_PO_SUB_LINE_COMPONENT ON
	(RCV_PO_SUB_LINE.PO_SUB_LINE_ID  = RCV_PO_SUB_LINE_COMPONENT.PO_SUB_LINE_ID and
	 RCV_PO_SUB_LINE.PO_SUB_LINE_IDB = RCV_PO_SUB_LINE_COMPONENT.PO_SUB_LINE_IDB and
	 RCV_PO_SUB_LINE.RCV_ID  = RCV_PO_SUB_LINE_COMPONENT.RCV_ID and
	 RCV_PO_SUB_LINE.RCV_IDB = RCV_PO_SUB_LINE_COMPONENT.RCV_IDB)

JOIN PO_LINE ON
	(PO_SUB_LINE.PO_LINE_ID  = PO_LINE.PO_LINE_ID and
	 PO_SUB_LINE.PO_LINE_IDB = PO_LINE.PO_LINE_IDB)

JOIN PO_LINE_COMPONENT ON
	(RCV_PO_SUB_LINE_COMPONENT.PO_LINE_ID  = PO_LINE_COMPONENT.PO_LINE_ID and
	 RCV_PO_SUB_LINE_COMPONENT.PO_LINE_IDB = PO_LINE_COMPONENT.PO_LINE_IDB and
	 RCV_PO_SUB_LINE_COMPONENT.SEQ_NO = PO_LINE_COMPONENT.SEQ_NO)

JOIN PO ON
	(PO_LINE.PO_ID = PO.PO_ID and
	PO_LINE.PO_IDB = PO.PO_IDB  and
	(PO_LINE.LINE_ALLOC_IND = ''N'' or PO_LINE.LINE_ALLOC_IND is null))

LEFT JOIN CODE_TABLE ON
	(RCV_PO_SUB_LINE_COMPONENT.REASON_CD = CODE_TABLE.TYPE_CD)

JOIN USR ON
	(RCV.REC_CREATE_USR_ID  = USR.USR_ID and
	 RCV.REC_CREATE_USR_IDB = USR.USR_IDB)

JOIN VEND ON
	(PO.VEND_ID  = VEND.VEND_ID and
	 PO.VEND_IDB = VEND.VEND_IDB)

JOIN LOC ON
	(PO_SUB_LINE.DELV_LOC_ID  = LOC.LOC_ID and
	 PO_SUB_LINE.DELV_LOC_IDB = LOC.LOC_IDB)

JOIN SUB_ACCT ON
	(SUB_ACCT.SUB_ACCT_ID  = PO_LINE.SUB_ACCT_ID and
	 SUB_ACCT.SUB_ACCT_IDB = PO_LINE.SUB_ACCT_IDB)

JOIN EXP_CODE ON
	(SUB_ACCT.EXP_CODE_ID  = EXP_CODE.EXP_CODE_ID and
	 SUB_ACCT.EXP_CODE_IDB = EXP_CODE.EXP_CODE_IDB)

JOIN CC ON
	(EXP_CODE.CC_ID  = CC.CC_ID and
	 EXP_CODE.CC_IDB = CC.CC_IDB)

JOIN CORP ON
	(CC.CORP_ID  = CORP.CORP_ID and
	 CC.CORP_IDB = CORP.CORP_IDB)

JOIN ITEM ON
	(PO_LINE_COMPONENT.ITEM_ID  = ITEM.ITEM_ID and
	 PO_LINE_COMPONENT.ITEM_IDB = ITEM.ITEM_IDB and
	 ITEM.COMPONENT_IND = ''Y'')

LEFT JOIN SUB_PROJECT ON
	(PO_LINE.SUB_PROJECT_ID  = SUB_PROJECT.SUB_PROJECT_ID and
	 PO_LINE.SUB_PROJECT_IDB = SUB_PROJECT.SUB_PROJECT_IDB)

LEFT JOIN PROJECT ON
	(SUB_PROJECT.PROJECT_ID  = PROJECT.PROJECT_ID and
	 SUB_PROJECT.PROJECT_IDB = PROJECT.PROJECT_IDB)

LEFT JOIN SUB_LEDGER ON
	(PO_LINE.SUB_LEDGER_ID  = SUB_LEDGER.SUB_LEDGER_ID and
	 PO_LINE.SUB_LEDGER_IDB = SUB_LEDGER.SUB_LEDGER_IDB and
	 SUB_LEDGER.CORP_ID = CC.CORP_ID and 
	 SUB_LEDGER.CORP_IDB = CC.CORP_IDB ) '

-- Query 4 of 4 
-- returns receipt lines items recieved by component where the parent po line has allocations. 
Select @string4 = '
UNION ALL
SELECT		PO.PO_ID,
		PO.PO_IDB,
		PO_LINE.PO_LINE_ID,
		PO_LINE.PO_LINE_IDB,
		PO.PO_NO,
		PO_LINE.LINE_NO, --used for testing/troubleshooting purposes only
		(PO_LINE_COMPONENT.QTY * PO_LINE.QTY), --extended order qty po line qty * po line comp qty
		RCV.RCV_DATE,
		RCV_PO_SUB_LINE_COMPONENT.QTY, --rcvd comp qty
		RCV_PO_SUB_LINE_COMPONENT.UM_CD, --rcvd comp um, same as order um
		(PO_LINE_COMPONENT.PRICE * (PO_LINE_ALLOC.PERCENT_NBR * .01)), --component price based on allocation percentage
		(((PO_LINE_COMPONENT.PRICE * RCV_PO_SUB_LINE_COMPONENT.QTY) * (PO_LINE_ALLOC.PERCENT_NBR * .01))), -- extended price, used for testing/troubleshooting purposes only
		PO_LINE_ALLOC.DOLLAR_AMT, --used for testing/troubleshooting purposes only
		PO_LINE_ALLOC.PERCENT_NBR, --used for testing/troubleshooting purposes only
                PO_LINE_COMPONENT.UM_CD,  --order comp um, same as rcvd um
		NULL, --COMPONENTS CANNOT BE RCVD IN ALT UM
		NULL, --COMPONENTS CANNOT BE RCVD IN ALT UM
		CORP.ACCT_NO, -- po line allocation corp info
		CORP.NAME,
		CC.ACCT_NO, -- po line allocation ccc info
		CC.NAME,
		EXP_CODE.ACCT_NO, -- po line allocation exp info
		EXP_CODE.NAME,
		SUB_ACCT.ACCT_NO, -- po line allocation sub info
		SUB_ACCT.NAME,
		''[Component]'', --item no
		ITEM.DESCR, --component item descr
		VEND.NAME,
		LOC.NAME,
		''N'', --Item ctlg ind
		USR.NAME,
		Case when LOC.LOC_TYPE = ''2''
            	then ''Y'' else ''N'' end,
		0, --PO_LINE_TAX
		CODE_TABLE.NAME, --component
		SUB_LEDGER.SubLedValue, --po line allocation data
		SUB_PROJECT.SUB_PROJ_CODE, --po line allocation data
		PROJECT.PROJ_CODE, --po line allocation data
		ISNULL(PO_LINE.LINE_ALLOC_IND,''N''), 
		PO_LINE_ALLOC.SEQ_NO, --used for testing/troubleshooting purposes and order by clause
		PO_LINE_COMPONENT.SEQ_NO, --used for testing/troubleshooting purposes and order by clause
		case when ITEM.COMPONENT_IND is null then ''N''
	     	when ITEM.COMPONENT_IND = '''' then ''N''  --this is adressed in pcr 34918, should always be Y in this query
	     	else ITEM.COMPONENT_IND end,
		ISNULL(PO_SUB_LINE.RCV_COMP_IND, ''N''), --should always be Y in this query
		0 -- PCR 44420 sets NON_CTLG_ALT_UM_FLAG 
FROM 	RCV
JOIN RCV_PO_SUB_LINE ON
	(RCV.RCV_ID  = RCV_PO_SUB_LINE.RCV_ID and
	 RCV.RCV_IDB = RCV_PO_SUB_LINE.RCV_IDB)

JOIN PO_SUB_LINE ON
	(RCV_PO_SUB_LINE.PO_SUB_LINE_ID  = PO_SUB_LINE.PO_SUB_LINE_ID and
	 RCV_PO_SUB_LINE.PO_SUB_LINE_IDB = PO_SUB_LINE.PO_SUB_LINE_IDB and
	 PO_SUB_LINE.RCV_COMP_IND = ''Y'' )

JOIN RCV_PO_SUB_LINE_COMPONENT ON
	(RCV_PO_SUB_LINE.PO_SUB_LINE_ID  = RCV_PO_SUB_LINE_COMPONENT.PO_SUB_LINE_ID and
	 RCV_PO_SUB_LINE.PO_SUB_LINE_IDB = RCV_PO_SUB_LINE_COMPONENT.PO_SUB_LINE_IDB and
	 RCV_PO_SUB_LINE.RCV_ID  = RCV_PO_SUB_LINE_COMPONENT.RCV_ID and
	 RCV_PO_SUB_LINE.RCV_IDB = RCV_PO_SUB_LINE_COMPONENT.RCV_IDB)

JOIN PO_LINE ON
	(PO_SUB_LINE.PO_LINE_ID  = PO_LINE.PO_LINE_ID and
	 PO_SUB_LINE.PO_LINE_IDB = PO_LINE.PO_LINE_IDB)

JOIN PO_LINE_COMPONENT ON
	(RCV_PO_SUB_LINE_COMPONENT.PO_LINE_ID = PO_LINE_COMPONENT.PO_LINE_ID and
	RCV_PO_SUB_LINE_COMPONENT.PO_LINE_IDB = PO_LINE_COMPONENT.PO_LINE_IDB and
	RCV_PO_SUB_LINE_COMPONENT.SEQ_NO = PO_LINE_COMPONENT.SEQ_NO)

JOIN PO ON
	(PO_LINE.PO_ID  = PO.PO_ID and
	 PO_LINE.PO_IDB = PO.PO_IDB )

JOIN  PO_LINE_ALLOC ON
	(PO_LINE_ALLOC.PO_LINE_ID  = RCV_PO_SUB_LINE_COMPONENT.PO_LINE_ID and
	 PO_LINE_ALLOC.PO_LINE_IDB = RCV_PO_SUB_LINE_COMPONENT.PO_LINE_IDB and
         PO_LINE_COMPONENT.SEQ_NO  = RCV_PO_SUB_LINE_COMPONENT.SEQ_NO and
	 PO_LINE.LINE_ALLOC_IND = ''Y'')

LEFT JOIN CODE_TABLE ON
	(RCV_PO_SUB_LINE_COMPONENT.REASON_CD = CODE_TABLE.TYPE_CD)

JOIN USR ON
	(RCV.REC_CREATE_USR_ID  = USR.USR_ID and
	 RCV.REC_CREATE_USR_IDB = USR.USR_IDB)

JOIN VEND ON
	(PO.VEND_ID  = VEND.VEND_ID and
	 PO.VEND_IDB = VEND.VEND_IDB)

JOIN LOC ON
	(PO_SUB_LINE.DELV_LOC_ID  = LOC.LOC_ID and
	 PO_SUB_LINE.DELV_LOC_IDB = LOC.LOC_IDB)

JOIN SUB_ACCT ON
	(SUB_ACCT.SUB_ACCT_ID  = PO_LINE_ALLOC.SUB_ACCT_ID and
	 SUB_ACCT.SUB_ACCT_IDB = PO_LINE_ALLOC.SUB_ACCT_IDB)

JOIN EXP_CODE ON
	(SUB_ACCT.EXP_CODE_ID  = EXP_CODE.EXP_CODE_ID and
	 SUB_ACCT.EXP_CODE_IDB = EXP_CODE.EXP_CODE_IDB)

JOIN CC ON
	(EXP_CODE.CC_ID  = CC.CC_ID and
	 EXP_CODE.CC_IDB = CC.CC_IDB)

JOIN CORP ON
	(CC.CORP_ID  = CORP.CORP_ID and
	 CC.CORP_IDB = CORP.CORP_IDB)

JOIN ITEM ON
	(PO_LINE_COMPONENT.ITEM_ID  = ITEM.ITEM_ID and
	 PO_LINE_COMPONENT.ITEM_IDB = ITEM.ITEM_IDB and
	 ITEM.COMPONENT_IND = ''Y'')

LEFT JOIN SUB_PROJECT ON
	(PO_LINE_ALLOC.SUB_PROJECT_ID  = SUB_PROJECT.SUB_PROJECT_ID and
	 PO_LINE_ALLOC.SUB_PROJECT_IDB = SUB_PROJECT.SUB_PROJECT_IDB)

LEFT JOIN PROJECT ON
	(SUB_PROJECT.PROJECT_ID  = PROJECT.PROJECT_ID and
	 SUB_PROJECT.PROJECT_IDB = PROJECT.PROJECT_IDB)

LEFT JOIN SUB_LEDGER ON
	(PO_LINE.SUB_LEDGER_ID  = SUB_LEDGER.SUB_LEDGER_ID and
	 PO_LINE.SUB_LEDGER_IDB = SUB_LEDGER.SUB_LEDGER_IDB and
	 SUB_LEDGER.CORP_ID = CC.CORP_ID and 
	 SUB_LEDGER.CORP_IDB = CC.CORP_IDB ) '

select @string = ' WHERE PO.PO_IDB = ' + @c_DB_ID_char

if @p_corp_id <> '' and @p_corp_id is not null
Select @string = @string + ' and CORP.CORP_ID in ' + @p_corp_id + ' and CORP.CORP_IDB = ' + @c_DB_ID_char

if @p_rcv_beg_date <> '' and @p_rcv_beg_date IS NOT NULL
Select @string = @string + ' and RCV.RCV_DATE >= ''' + @p_rcv_beg_date + ''''

if @p_rcv_end_date <> '' and @p_rcv_end_date IS NOT NULL
Select @string = @string + ' and RCV.RCV_DATE <= ''' + @p_rcv_end_date + ''''

if @p_po_sub_line_cc_id <> '' and @p_po_sub_line_cc_id IS NOT NULL
Select @string = @string + ' and PO_SUB_LINE.CC_ID in ' + @p_po_sub_line_cc_id + ' and PO_SUB_LINE.CC_IDB = ' + @c_DB_ID_char

if @p_sub_acct_id <> '' and @p_sub_acct_id IS NOT NULL
Select @string = @string + ' and SUB_ACCT.SUB_ACCT_ID in ' + @p_sub_acct_id + ' and SUB_ACCT.SUB_ACCT_IDB = ' + @c_DB_ID_char

if @p_po_id <> '' and @p_po_id is not null
Select @string = @string + ' and PO.PO_ID in ' + @p_po_id

if @p_vend_id  <> '' and @p_vend_id  is not null
Select @string = @string + ' and PO.VEND_ID in ' + @p_vend_id 

if @p_item_id <> '' and @p_item_id is not null
Select @string = @string + ' and PO_LINE.ITEM_ID in ' + @p_item_id

if @p_delv_loc_id <> '' and @p_delv_loc_id is not null
Select @string = @string + ' and PO_SUB_LINE.DELV_LOC_ID in ' + @p_delv_loc_id 

if @p_project_id <> '' and @p_project_id is not null
Select @string = @string + ' and PROJECT.PROJECT_ID in ' + @p_project_id 

if @p_sub_project_id <> '' and @p_sub_project_id is not null
Select @string = @string + ' and SUB_PROJECT.SUB_PROJECT_ID in ' + @p_sub_project_id 

if @p_sub_ledger_rule <> '' and @p_sub_ledger_rule is not null
Select @string = @string + ' and SUB_LEDGER.SUB_LEDGER_RULE_ID in (SELECT SUB_LEDGER_RULE_ID FROM #SUBLEDGE_RULE ) and SUB_LEDGER.SUB_LEDGER_RULE_IDB = ' + @c_DB_ID_char 

if @p_sub_ledger_val <> '' and @p_sub_ledger_val is not null
Select @string = @string + ' and SUB_LEDGER.SubLedValue in ' + @p_sub_ledger_val

exec(@string1 + @string + @string2 + @string + @string3 + @string + @string4 + @string)

----------------------------------------------------------------------------------------

UPDATE 	#RCVRPT
	set  po_line_tax = case
		when (#RCVRPT.LINE_ALLOC_IND = 'N' or #RCVRPT.LINE_ALLOC_IND IS NULL)
		then (select (IsNull(SUM(PO_LINE_TAX.TAX_RATE),0))  -- parent lines
			from PO_LINE_TAX 
			where   PO_LINE_TAX.PO_LINE_ID  = #RCVRPT.PO_LINE_ID and
			        PO_LINE_TAX.PO_LINE_IDB = #RCVRPT.PO_LINE_IDB and
			        (PO_LINE_TAX.SELF_ASSESS_IND = 'N' or PO_LINE_TAX.SELF_ASSESS_IND is null) )
		when (#RCVRPT.LINE_ALLOC_IND = 'Y')
		then (select IsNull(SUM(PO_LINE_ALLOC_TAX.TAX_RATE),0) --allocations lines
			from PO_LINE_ALLOC_TAX  
			where 	PO_LINE_ALLOC_TAX.PO_LINE_ID  = #RCVRPT.PO_LINE_ID and
			        PO_LINE_ALLOC_TAX.PO_LINE_IDB = #RCVRPT.PO_LINE_IDB and
			        PO_LINE_ALLOC_TAX.ALLOC_SEQ_NO  =  #RCVRPT.ALLOC_SEQ_NO and
			       ( PO_LINE_ALLOC_TAX.SELF_ASSESS_IND = 'N' or PO_LINE_ALLOC_TAX.SELF_ASSESS_IND is null ))
				else 0
		end

-- Updates #RCVRPT.NON_CTLG_ALT_UM_FLAG and sets it to one for
-- Non-catlog items that have been received in alternative UM.  
-- PCR 44420.  Can not correctly calculate the extend cost for these items.
-- This flag used to set extended cost to zero and to put footnote on line.
UPDATE 	#RCVRPT SET NON_CTLG_ALT_UM_FLAG = 1 WHERE RCV_PO_SUB_LINE_ALT_UM_CD IS NOT NULL
AND ITEM_CTLG_ITEM_IND = 'N'
----------------------------------------------------------------------------------------
--Final Select Notes:
--These fields are returned for testing/troubleshooting purposes only: 
--PO_LINE_NO,COMP_SEQ_NO,ALLOC_SEQ_NO,RCVD_PRICE,ALLOC_DOLLAR_AMT,ALLOC_PERCENT_NBR

Select
	RCV_RCV_DATE,
	VENDOR_NAME,
	RCV_NAME,
	PO_PO_NO,
	PO_LINE_QTY,
	PO_LINE_UM_CD,
	RCV_PO_SUB_LINE_QTY,
	RCV_PO_SUB_LINE_UM_CD,
	PO_LINE_PRICE,
	RCV_PO_SUB_LINE_ALT_QTY,
	RCV_PO_SUB_LINE_ALT_UM_CD,
	po_line_tax = (RCVD_PRICE * po_line_tax),
	ITEM_ITEM_NO,
	ITEM_DESC,
	ITEM_CTLG_ITEM_IND,
	ITEM_COMP_IND,
	RCV_COMP_IND,
	LINE_ALLOC_IND,
	CORP_ACCT_NO,
	CORP_NAME,
	CC_ACCT_NO,
	CC_NAME,
	EXP_CODE_ACCT_NO,
	EXP_CODE_NAME,
	SUB_ACCT_ACCT_NO,
	SUB_ACCT_NAME,
	DELV_LOC_NAME,
	is_delv_loc_supp_loc,
	CODE_TABLE_NAME,
	SubLedValue,
	SUB_PROJ_CODE,
	PROJ_CODE,
	@p_page_break page_break,
	@p_group_by_loc group_by_loc,
	PO_LINE_NO,
	COMP_SEQ_NO,
	ALLOC_SEQ_NO,
	RCVD_PRICE,
	ALLOC_DOLLAR_AMT,
	ALLOC_PERCENT_NBR,
	NON_CTLG_ALT_UM_FLAG 
	
From #RCVRPT
ORDER BY 
	RCV_NAME,
	RCV_RCV_DATE,
	VENDOR_NAME
	
	--CORP_ACCT_NO ASC,
    --CC_ACCT_NO ASC,
    --EXP_CODE_ACCT_NO ASC,
	--SUB_ACCT_ACCT_NO ASC,
	--RCV_RCV_DATE ASC,
	--ITEM_ITEM_NO ASC,  
	--COMP_SEQ_NO  ASC,
	--ALLOC_SEQ_NO ASC
end

drop table #RCVRPT
drop table #SUBLEDGE_RULE


