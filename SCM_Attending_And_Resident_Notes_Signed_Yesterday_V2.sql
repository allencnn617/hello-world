USE [BI]
GO
/****** Object:  StoredProcedure [IBU].[SCM_Attending_And_Resident_Notes_Signed_Yesterday_V2]    Script Date: 8/22/2016 12:37:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*************************************
General Information
-- Purpose:  identify visits which are possibly ready for coding
-- Date:  7/8/2016
-- Author:  Connie Allen
-- Source Systems:  SCM
-- Notes: interim data extract until a module of 3M's encoder can be implemented for computer assisted coding
			Justin does not care about documents that have been authored by a resident but are not yet signed by an attending; 
			only return complete or finalized documents; return documents for all billable providers, not just residents and attendings
			Pamela will use the extract to put the data into a SQL database accessed via Microsoft Access
-- Associated Tickets:  WO0000000011944
-- Business Contact:  Justin Perry
-- Technical Contact: Pamela J Roundtree, Steve (Stephen L) Crawford
					Steve Welch
-- Informaticist:  Cathy (Catherine S) Roe
-- Other Contacts:  Sharon MacLaughlin, Project Manager of the IBU Revenue Management project

Change History
-- Version Number: 2
-- Author: Connie Allen
-- Date: 8/11/2016 
-- Purpose: change Attending column to be the Authored Provider if it would otherwise be blank.  
			It is currently blank when the document is created in another application and the entered by and 
			updated by is "eclipsys, KEEP" from the interface message.  This occurs on Operative Reports.
-- Description of Changes: replace in #temp population
-- Associated Tickets: WO0000000013573
-- Change Requestor: Justin Perry
-- Technical Contact: (O)
-- Informaticist: Cathy Roe
-- Other Contacts: Sharon MacLaughlin, PM 

-- Version Number: 2
-- Author: Connie Allen
-- Date: 8/19/2016 
-- Purpose: change Is_It_Finalized column to be the document status and signature status; include documents in all statuses
-- Description of Changes: 
-- Associated Tickets: WO0000000013736
-- Change Requestor: Justin Perry
-- Technical Contact: (O)
-- Informaticist: Cathy Roe
-- Other Contacts: Sharon MacLaughlin, PM 

-- Version Number: 2
-- Author: Connie Allen
-- Date: 8/22/2016 
-- Purpose: include documents authored by anyone if they were signed by a billable provider
-- Description of Changes: change #Providers to all users
--							add field to tell if the provider is a billable provider
--							replace the Attending ID and Attending columns with the document signer�s ID and document signer
--							for documents interfaced into SCM look for Author to be a billable provider
-- Associated Tickets: WO0000000014052
-- Change Requestor: Justin Perry
-- Technical Contact: (O)
-- Informaticist: Cathy Roe
-- Other Contacts: Sharon MacLaughlin, PM 

Approvals
-- Architecture Approval Date:
-- Architect:
-- Data Quality Approval Date:
-- Data Quality Specialist:
-- Data Specialist Approval Date: 
-- Data Specialist:
**************************************/

--Stored Procedure Name and Definition
ALTER PROC [IBU].[SCM_Attending_And_Resident_Notes_Signed_Yesterday_V2]
AS
	 --	BEGIN
	 --Standard Settings
	 SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	 SET NOCOUNT ON

	 --If they exisit, drop Temporary Tables
	 IF OBJECT_ID('tempdb..#Providers') IS NOT NULL
		 BEGIN
			 DROP TABLE #Providers
		 END
	 IF OBJECT_ID('tempdb..#temp') IS NOT NULL
		 BEGIN
			 DROP TABLE #temp
		 END
	 IF OBJECT_ID('tempdb..#Attestation') IS NOT NULL
		 BEGIN
			 DROP TABLE #Attestation
		 END
	 IF OBJECT_ID('tempdb..#TopStatus') IS NOT NULL
		 BEGIN
			 DROP TABLE #TopStatus
		 END
	 --Variable Definitions

	 DECLARE @FromDate    DATETIME
	 DECLARE @ToDate    DATETIME

	 -- from 12:00AM to 23:59
	 SELECT
		 @FromDate = DATEADD(d, -1, DATEADD(d, DATEDIFF(d, 0, GETDATE()), 0))
	 SELECT
		 @ToDate = DATEADD(s, -1, DATEADD(d, DATEDIFF(d, 0, GETDATE()), 0)) 
	 --DEBUG:  	 	 SET @FromDate = '2016-08-22 00:00:00.000' SET @ToDate = '2016-08-22 23:59:59.997'-- GETDATE()
	 --Data Processing
	 --get resident and attending physicians because the report is only for documents created and signed by these occupations in SCM
	 SELECT
		 cp.GUID
	   , cp.DisplayName
	   , id.IDCode
	   , CV3User.OccupationCode
	   , Division = ISNULL(
						  (
							  SELECT TOP 1
								  sg.Description
							  FROM   SCMPROD1.dbo.CV3UserSignatureGroupXRef x
							  LEFT OUTER JOIN SCMPROD1.dbo.CV3SignatureGroup sg
									 ON x.SignatureGroupGUID = sg.GUID
							  WHERE sg.Description NOT IN('UKCMC Physicians Group')
									 AND (x.ExpiryDtm IS NULL
										  OR x.ExpiryDtm > GETDATE())
									 AND CV3User.GUID = x.UserGUID
						  ), 'No_Security_Group_Besides_UKCMC Physicians Group')
-- Date: 8/22/2016 
-- Purpose: include documents authored by anyone if they were signed by a billable provider
-- Description of Changes: change #Providers to all users
--							add field to tell if the provider is a billable provider
		, Billable_Provider = CASE WHEN SCMPROD1.dbo.CV3User.OccupationCode IN
	 (
		 'Clinical Psychologist'
	   , 'Physician'
	   , 'Physician Assistant'
	   , 'Licensed Clinical Social Worker'
	   , 'Nurse Practitioner'
	   , 'Attending'
	   , 'Resident'
	 ) THEN 'Yes' ELSE 'No' END 
	 INTO
		 #Providers
	 FROM SCMPROD1.dbo.CV3CareProvider AS cp --CI:  GUID
	 JOIN SCMPROD1.dbo.CV3CareProviderID id --CI:  ProviderGUID
		  ON cp.GUID = id.ProviderGUID
	 JOIN SCMPROD1.dbo.CV3User --CI:  GUID
		  ON cp.GUID = CV3User.GUID
			 AND (CV3User.ExpiryDtm IS NULL
				  OR CV3User.ExpiryDtm > (GETDATE() - 1))
	 WHERE 
/*	 -- Date: 8/22/2016 
-- Purpose: include documents authored by anyone if they were signed by a billable provider
-- Description of Changes: change #Providers to all users
	 SCMPROD1.dbo.CV3User.OccupationCode IN
	 (
		 'Clinical Psychologist'
	   , 'Physician'
	   , 'Physician Assistant'
	   , 'Licensed Clinical Social Worker'
	   , 'Nurse Practitioner'
	   , 'Attending'
	   , 'Resident'
	 )
		   AND*/ 
		   (CV3User.ExpiryDtm IS NULL
				OR CV3User.ExpiryDtm > @FromDate)
		   AND id.ProviderIDTypeCode = 'Primary ID'
		   AND cp.Active = 1
		   AND id.Active = 1
		   AND CV3User.Active = 1
		   AND (CV3User.ExpiryDtm IS NULL
				OR CV3User.ExpiryDtm >= @FromDate)
		   AND id.IDCode NOT LIKE 'OUTREF%'--The people that have IDCode starting with OUTREF are not actual user accounts in SCM, so they can�t login to sign anything.  It looks like those might be external referring physicians that were added for the faxing
	 --DEBUG:  	  	 and cp.GUID = 9000018974001190
	 --DEBUG:  	  	 SELECT			*		FROM #Providers  where Billable_Provider = 'Yes'--displayname like 'Langley%' order by IDCode--guid--	  AND cp.DisplayName LIKE 'Anderson   MD, Eric'--services, KEEP'--Model%'
	 CREATE CLUSTERED INDEX P ON #Providers(GUID)

	 --get all document changes authored or signed by these providers in the time frame
	 SELECT
		 cd.GUID AS                                                                      DocumentGUID
	   , cv.VisitIDCode AS                                                               HQ_Visit_Number
	   , cv.IDCode AS                                                                    MRN
	   , cv.ClientDisplayName AS                                                         Patient_Name
	   , cd.AuthoredDtm AS                                                               Author_Date
	   , cdh.CreatedWhen AS                                                              Signed_Date--
	   , CONVERT(    DATETIME, cd.ServiceDtmUTC) AS                                      Date_Of_Service
	   , ISNULL(drc.SubCategoryName, ISNULL(drc.MasterCategoryName, cd.DocumentName)) AS Note_Type
	   , cd.DocumentName AS                                                              Document
	   , pcd.GUID AS                                                                     Document_Name_GUID
	   , #Providers.IDCode AS                                                            Authoring_Provider_ID
	   , #Providers.DisplayName AS                                                       Authoring_Provider

/*8/11/2016  replaced
  , CP.IDCode AS                                                                    Attending_ID
  , CP.DisplayName AS                                                               Attending*/
/*8/22/2016 replaced	   , ISNULL(cp.IDCode, #Providers.IDCode) AS                                         Attending_ID
	   , ISNULL(cp.DisplayName, #Providers.DisplayName) AS                               Attending*/
				, ISNULL(ISNULL(InterfacedDocSigner.IDCode,cp.IDCode),#Providers.IDCode) AS Document_Signer_ID
				, ISNULL(ISNULL(InterfacedDocSigner.DisplayName,cp.DisplayName),#Providers.DisplayName) AS Document_Signer


		 --end change 8/11/2016
	   , CASE
			 WHEN cd.AuthoredProviderGUID IN
	 (
		 SELECT
			 GUID
		 FROM   #Providers
		 WHERE OccupationCode = 'Resident'
	 )
			 THEN 'Yes'
			 ELSE 'No'
		 END AS                                                                          Resident_Involvement
		 --8/19/2016
		 --, 'Finalized' AS                                                                  'Is_It_Finalized'
	   , CASE
			 WHEN cdh.DocumentStatusType = 1
			 THEN 'Incomplete,Appended'
			 WHEN cdh.DocumentStatusType = 2
			 THEN 'Complete,Appended'
			 WHEN cdh.DocumentStatusType = 3
			 THEN 'Final,Appended'
			 WHEN cdh.DocumentStatusType = 4
			 THEN 'Appended'
			 WHEN cdh.DocumentStatusType = 5
			 THEN 'Incomplete'
			 WHEN cdh.DocumentStatusType = 6
			 THEN 'Complete'
			 WHEN cdh.DocumentStatusType = 7
			 THEN 'Final'
			 WHEN cdh.DocumentStatusType = 8
			 THEN 'Cancelled'
			 WHEN cdh.DocumentStatusType = 9
			 THEN 'In-Progress'
			 WHEN cdh.DocumentStatusType = 0/*this field is only 1 character as of 8/19/2016*/
			 THEN 'No Document status'
			 ELSE 'Check SCM'
		 END AS                                                                          'Is_It_Finalized'
		 --if a document was authored by a resident without a security group, then get the security group of the attending who is co-signing the document
	   , CASE
			 WHEN CP.Division = 'No_Security_Group_Besides_UKCMC Physicians Group'
			 THEN #Providers.Division
			 ELSE CP.Division
		 END AS                                                                          Division
	   , cv.ClientGUID
	   , cv.ChartGUID
	   , cv.GUID AS                                                                      clientvisitGUID
	   , cd.AuthoredProviderGUID
	   --DEBUG:  	   ,#Providers.Billable_Provider,cdh.UserGUID
	 INTO
		 #temp
	 FROM SCMPROD1.dbo.CV3ClientVisit cv(nolock)
	 JOIN SCMPROD1.dbo.CV3ClientDocument--CUR CI:  ClientGUID, ChartGUID, PatCareDocGUID, AuthoredDtm, ArcType 
	 cd(nolock)
		  ON cv.ClientGUID = cd.ClientGUID
			 AND cv.ChartGUID = cd.ChartGUID
	 JOIN SCMPROD1.dbo.CV3PatientCareDocument pcd
		  ON cd.PatCareDocGUID = pcd.GUID
			 AND cd.AuthoredDtm > (GETDATE() - 365)
			 AND cd.ArcType = CASE
								  WHEN cv.ArcType = 99
								  THEN 0
								  ELSE cv.ArcType
							  END
			 AND cd.iscanceled = 0
			 --AND CD.ToBeSigned = 0--8/16/2016 Justin wants them all now
	JOIN #Providers(nolock) --CI:  GUID
		  ON #Providers.GUID = cd.AuthoredProviderGUID
	JOIN SCMPROD1.dbo.CV3ClientDocHistory--CI:  ClientGUID, ClientDocGUID, HistoryDtm, ArcType; NCI:  UserGUID, ClientDocGUID, HistoryDtm
	 cdh(nolock)
		  ON cv.ClientGUID = cdh.ClientGUID
			 AND cd.GUID = cdh.ClientDocGUID
			 AND cdh.HistoryDtm BETWEEN @FromDate AND @ToDate
			 AND cd.ArcType = cdh.ArcType
			 AND cv.GUID = cd.ClientVisitGUID 
/*8/19/2016 	AND cdh.SignatureStatusType = 4 -- CV3ClientDocHistory.SignatureStatus = 4 when Signed in Full
				AND cdh.DocumentStatusType IN(2, 3, 6, 7) 
/*CV3ClientDocHistory	DocumentStatus	4	Appended
CV3ClientDocHistory	DocumentStatus	8	Cancelled
CV3ClientDocHistory	DocumentStatus	6	Complete
CV3ClientDocHistory	DocumentStatus	2	Complete,Appended
CV3ClientDocHistory	DocumentStatus	7	Final
CV3ClientDocHistory	DocumentStatus	3	Final,Appended
CV3ClientDocHistory	DocumentStatus	9	In-Progress
CV3ClientDocHistory	DocumentStatus	5	Incomplete
CV3ClientDocHistory	DocumentStatus	1	Incomplete,Appended
CV3ClientDocHistory	DocumentStatus	0	No Document status*/*/
-- Date: 8/22/2016 
-- Purpose: include documents authored by anyone if they were signed by a billable provider
-- Description of Changes: change #Providers to all users
--							add field to tell if the provider is a billable provider
			AND (#Providers.Billable_Provider = 'Yes'--authored by a billable provider
				OR cdh.UserGUID IN (SELECT GUID FROM #Providers WHERE Billable_Provider = 'Yes')--signed by a billable provider
--							for documents interfaced into SCM look for Author to be a billable provider
				OR (cdh.UserGUID = (SELECT GUID FROM SCMPROD1.dbo.CV3User WHERE DisplayName = 'services, KEEP')
					AND cd.AuthoredProviderGUID IN (SELECT GUID FROM #Providers WHERE Billable_Provider = 'Yes'))
				)
	 LEFT OUTER JOIN #Providers cp
		  ON cp.GUID = cdh.UserGUID
	/*	  replace the Attending ID and Attending columns with the document signer�s ID and document signer
			 AND cp.GUID IN
	 (
		 SELECT
			 GUID
		 FROM  #Providers
		 WHERE OccupationCode = 'Attending'
	 )*/
	 LEFT OUTER JOIN SCMPROD1.dbo.CV3DocumentReviewCategory drc
		  ON pcd.DocReviewCategoryGUID = drc.GUID
			 AND drc.Active = 1
--8/22/2016 get additional signers for interfaced in documents, e.g. Operative Report
	LEFT OUTER JOIN SCMProd1.dbo.CV3ClientDocProviderXref xref --CI:  ClientGUID, ClientDocGUID, HistGroupCounter, ArcType
            ON ( cd.GUID = xref.ClientDocGUID AND
                 cd.ClientGUID = xref.ClientGUID AND
                 cd.AuthorGroupCounter = xref.HistGroupCounter AND
				 cd.ArcType = xref.ArcType
				AND AuthorSigned = 1
				 AND xref.ProviderType = (SELECT MAX(ProviderType) FROM SCMPROD1.dbo.CV3ClientDocProviderXref
											WHERE xref.ClientGUID = CV3ClientDocProviderXref.ClientGUID
											AND xref.ClientDocGUID = CV3ClientDocProviderXref.ClientDocGUID
											AND xref.HistGroupCounter = CV3ClientDocProviderXref.HistGroupCounter
											AND xref.ArcType = CV3ClientDocProviderXref.ArcType
											)
				)
LEFT OUTER JOIN #Providers InterfacedDocSigner ON  xref.ProviderGUID = InterfacedDocSigner.GUID AND InterfacedDocSigner.Billable_Provider = 'Yes'
	 WHERE(cv.VisitStatus = 'ADM'
		   OR cv.DischargeDtm > (GETDATE() - 365)
		   OR cv.CloseDtm > (GETDATE() - 365))
		  AND cd.EntryType IN
	 (
		 1
	   , 4
	 ) -- 1 = FreeText; 2 = Knowledge Tree; 3 = Flowsheet 4 = Structured Note
	 --DEBUG: 	 AND cd.GUID = 9028309376702040--
	 --DEBUG: 	 AND cd.GUID = 9028309376702040--		 
 --DEBUG: 	 	 SELECT *  FROM #temp where Document = 'Operative Report'--MCS Note'--Consult%' --debug:  	 and cv.IDCode = '3000000509'--purple pen '  -- and HQ_Visit_Number = '004463246-6191' --ORDER BY 	Note_Type-- JOIN SXACDObservationParameter o--CI:  ClientGUID, ChartGUID, ObsMasterItemGUID, RecordedDtm 	 ON #temp.ClientGUID = o.ClientGUID AND #temp.ChartGUID = o.ChartGUID 	 AND o.ObsMasterItemGUID IN (SELECT GUID FROM CV3ObsCatalogMasterItem WHERE Name LIKE 'uk attending attest stmt%')	 AND o.IsCanceled = 0 where HQ_Visit_Number = '007034895-6195'

	 CREATE CLUSTERED INDEX T ON #temp
	 (ClientGUID, ChartGUID, ClientVisitGUID, DocumentGUID, Signed_Date
	 )

/*********************************************************
list the last active input values 
**********************************************************/
	 SELECT DISTINCT
		 t.*
	 INTO
		 #TopStatus
	 FROM
	 (
		 SELECT
			 y.ClientGUID
		   , y.ChartGUID
		   , y.clientvisitGUID
		   , y.DocumentGUID
		   , y.AuthoredProviderGUID
		   , MAX(y.Signed_Date) AS maxSigned_Date
		 FROM #temp AS y
		 GROUP BY
			 y.ClientGUID
		   , y.ChartGUID
		   , y.clientvisitGUID
		   , y.DocumentGUID
		   , y.AuthoredProviderGUID
	 ) AS x
	 INNER JOIN #temp t
	 ON t.ClientGUID = x.ClientGUID
		AND t.ChartGUID = x.ChartGUID
		AND t.clientvisitGUID = x.clientvisitGUID
		AND t.DocumentGUID = x.DocumentGUID
		AND t.Signed_Date = x.maxSigned_Date 
	 --DEBUG:  			select * from #TopStatus

	 SELECT
		 #TopStatus.*
	   ,
	 (
		 SELECT TOP 1
			 o.ObservationGUID
		 FROM   SCMPROD1.dbo.SXACDObservationParameter o --CI:  ClientGUID, ChartGUID, ObsMasterItemGUID, RecordedDtm; NCI:  ObservationDocumentGUID, RecordedDtm
		 WHERE #TopStatus.ClientGUID = o.ClientGUID
			   AND #TopStatus.ChartGUID = o.ChartGUID
			   AND o.ObsMasterItemGUID IN
		 (
			 SELECT
				 GUID
			 FROM  SCMPROD1.dbo.CV3ObsCatalogMasterItem
			 WHERE Name LIKE 'uk attending attest stmt%'
		 )
			   AND o.RecordedDtm > (GETDATE() - 365)
			   AND o.IsCanceled = 0
			   AND o.OwnerGUID = #TopStatus.DocumentGUID
	 ) AS Attestation_GUID
	   ,
	 (
		 SELECT TOP 1
			 SOBS.Value
		 FROM  SCMPROD1.dbo.SXACDObservationParameter o --CI:  ClientGUID, ChartGUID, ObsMasterItemGUID, RecordedDtm
		 JOIN SCMPROD1.dbo.SCMObsFSListValues SOBS --CI:  ClientGUID, ParentGUID
			   ON o.ClientGUID = SOBS.ClientGUID    --Index, without this line, query will run very slow...
				  AND o.ObservationDocumentGUID = SOBS.ParentGUID
				  AND SOBS.Active = 1
		 WHERE #TopStatus.ClientGUID = o.ClientGUID
			   AND #TopStatus.ChartGUID = o.ChartGUID
			   AND o.ObsMasterItemGUID IN
		 (
			 SELECT
				 GUID
			 FROM  SCMPROD1.dbo.CV3ObsCatalogMasterItem
			 WHERE Name = 'md doc document topic 2 rd'
		 )
			   AND o.RecordedDtm > (GETDATE() - 365)
			   AND o.IsCanceled = 0
			   AND o.OwnerGUID = #TopStatus.DocumentGUID
	 ) AS Service
		 INTO
		 #Attestation
	 FROM #TopStatus 
	 --DEBUG:  SELECT	* FROM #Attestation
	 --Final Result Sets
	 SELECT DISTINCT
		 DocumentGUID
	   , HQ_Visit_Number
	   , MRN
	   , Patient_Name
	   , Author_Date
	   , Signed_Date
	   , Date_Of_Service
	   , Note_Type
	   , Document
	   , Document_Name_GUID
	   , Authoring_Provider_ID
	   , Authoring_Provider

	   /*8/22/2016 replaced
	   , Attending_ID
	   , Attending*/
	   , Document_Signer_ID
	   , Document_Signer

	   , Resident_Involvement
	   , Is_It_Finalized
	   , CASE
			 WHEN Attestation_GUID IS NOT NULL
			 THEN 'Yes'
			 ELSE 'No'
		 END AS Attestation_Present
	   , Service
	   , FromDate = @FromDate
	   , ToDate = @ToDate
	   , t.Division
	 FROM #Attestation t
	 --DEBUG:  WHERE Document like 'Consult%' and HQ_Visit_Number = '004463246-6191'
	 ORDER BY
		 t.Patient_Name
	   , t.Note_Type
	   , t.Date_Of_Service
	   , t.DocumentGUID
	
	 --If they exisit, drop Temporary Tables
	 IF OBJECT_ID('tempdb..#Providers') IS NOT NULL
		 BEGIN
			 DROP TABLE #Providers
		 END
	 IF OBJECT_ID('tempdb..#temp') IS NOT NULL
		 BEGIN
			 DROP TABLE #temp
		 END
	 IF OBJECT_ID('tempdb..#Attestation') IS NOT NULL
		 BEGIN
			 DROP TABLE #Attestation
		 END
	 IF OBJECT_ID('tempdb..#TopStatus') IS NOT NULL
		 BEGIN
			 DROP TABLE #TopStatus
		 END
--END
-- EXEC [IBU].[SCM_Attending_And_Resident_Notes_Signed_Yesterday]






GO


