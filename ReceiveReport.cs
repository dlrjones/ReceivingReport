using System;
using System.Collections.Specialized;
using System.Configuration;
using System.Data;
using System.IO;
using System.Windows.Forms;
using DTUtilities;
using OleDBDataManager;

namespace ReceivingReport
{
    public partial class ReceiveReport : Form
    {
        #region class variables
        DataSet dsRcvRpt = new DataSet();
        protected ODMDataFactory ODMDataSetFactory = null;
        private NameValueCollection ConfigData = null;
        DateTimeUtilities dtu = new DateTimeUtilities();
        private string dbConnect = null; 
       // private Hashtable Recievers = new Hashtable();//may not need this Hashtable
        private string xportPath = "";
        private string currentFileName = "ReceivingReport";
        private string currentRcvName = "";
        private string export = "";
        private string recipientList = "";
        private string[] recipients;
        private string TAB = (Convert.ToChar(9)).ToString(); // "        "
        private LogManager.LogManager lm = LogManager.LogManager.GetInstance();
        private OutputManager om = OutputManager.GetInstance();
        #endregion
        public ReceiveReport() {
            InitializeComponent();
            ConfigData = (NameValueCollection)ConfigurationManager.GetSection("appSettings");            
            lm.LogFilePath = ConfigData.Get("logFilePath");  //full path with trailing "\"
            lm.LogFile = ConfigData.Get("logFile");
            lm.Write(dtu.DateTimeToShortDate(DateTime.Now));
            om.Debug = Convert.ToBoolean(ConfigData.Get("debug"));
            om.AttachmentPath = ConfigData.Get("xport_path");
            om.DateTimeCoded = dtu.DateTimeCoded();
            om.LogPath = ConfigData.Get("logFilePath");
            recipientList = ConfigData.Get("recipientList");
            recipients = recipientList.Split(",".ToCharArray());
            ODMDataSetFactory = new ODMDataFactory();
            xportPath = ConfigData.Get("xport_path");
            dbConnect = ConfigData.Get("connect");
            foreach(string recipient in recipients)
            {
                om.RecipientList.Add(recipient);
            }
            LoadDataSet();            
        }

      //  private void ReceiveReport_Load(object sender, System.EventArgs e) {
          // if (xportPath.Length == 0) {
                
           //     ODMDataSetFactory = new ODMDataFactory();
           //     xportPath = ConfigData.Get("xport_path");
           //     dbConnect = ConfigData.Get("connect");

           // }
           //if (!done)
           //     LoadDataSet();
           // else {
           //     this.Close();
           //     Application.Exit();                
           // }
      //  }

        private string CommaCheck(string dbLine)
        {
            string lineItem = "";
            string[] colItem;
            char[] commas = new char[] {Convert.ToChar(44)};

            colItem = dbLine.Split(commas);
            if (colItem.Length > 1){
                foreach (string x in colItem){
                    lineItem += x + " ";
                }
            }else{
                lineItem = dbLine;
            }
            return lineItem.Trim();
        }

        private void LoadDataSet() {
            int test = 0;
            int rowCount = 0;
            int indx = 0;
            int nameCounter = 0;
            int rowTotal = 0;
            string startTime = "";
            string endTime = "";
            string name = "";
            string usrName = "";
            string tempDateVendor = "";
            string sumRow = "TOTAL ";
            string UOM = "";
            GetStartEndTime(ref startTime, ref endTime);

            ODMRequest Request = new ODMRequest();
            Request.ConnectString = dbConnect;
            Request.CommandType = CommandType.Text;
            //Request.Command = "HEMM_TEST.dbo.CheckForAllocations";
            Request.Command = "EXEC dbo.ReceiveReport;1 '(1000)','" + startTime + "','" + endTime + "', 'Y', '', '', 'N', '', '', '', '', '', '', '', '', 0";
            //"EXEC dbo.sp_hmcmm_ReceiveReport;1 '(1000)','" + startTime + "','" + endTime + "', 'Y', '', '', 'N', '', '', '', '', '', '', '', '', 0";
            try {
                
                dsRcvRpt = ODMDataSetFactory.ExecuteDataSetBuild(ref Request);
                if (dsRcvRpt.Tables.Count > 0)
                {
                    if (dsRcvRpt.Tables[0].Rows.Count > 0)
                    {
                        rowTotal = dsRcvRpt.Tables[0].Rows.Count;
                        export =
                            "RCV_DATE,VENDOR,RCV_NAME,PO_PO_NO,PO_LINE_QTY,PO_LINE_UM_CD,RCV_PO_SUB_LINE_QTY,RCV_PO_SUB_LINE_UM_CD,PO_LINE_PRICE," +
                            "RCV_PO_SUB_LINE_ALT_QTY,RCV_PO_SUB_LINE_ALT_UM_CD,po_line_tax,ITEM_ITEM_NO,ITEM_DESC,ITEM_CTLG_ITEM_IND,ITEM_COMP_IND," +
                            "RCV_COMP_IND,LINE_ALLOC_IND,CORP_ACCT_NO,CORP_NAME,CC_ACCT_NO,CC_NAME,EXP_CODE_ACCT_NO,EXP_CODE_NAME,SUB_ACCT_ACCT_NO," +
                            "SUB_ACCT_NAME,DELV_LOC_NAME,is_delv_loc_supp_loc,CODE_TABLE_NAME,SubLedValue,SUB_PROJ_CODE,PROJ_CODE,page_break," +
                            "group_by_loc,PO_LINE_NO,COMP_SEQ_NO,ALLOC_SEQ_NO,RCVD_PRICE,ALLOC_DOLLAR_AMT,ALLOC_PERCENT_NBR,NON_CTLG_ALT_UM_FLAG" +
                            Environment.NewLine;
                        //om.ColHeaders = export;
                        om.RowData.Add(export);
                        export = "";
                        while (rowCount < rowTotal)
                        {
                            // Console.Write(rowCount + " ");
                            //The name of the receiving person is the third column in the result set (RCV_NAME). In order to display a total of that
                            //person's 'receivings', I need to save off the first two columns of data in the event that the RCV_NAME has changed
                            //and I need to insert a totals row. tempDateVendor saves the RCV_DATE & VENDOR columns for that purpose.
                            tempDateVendor =
                                CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                "|";
                            tempDateVendor +=
                                CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                "|";

                            name = CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim());
                            usrName = dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[2].ToString().Trim();
                            if (usrName.Equals("PMM EDI Server"))
                                test++;
                            if (!(usrName.Trim().Equals("PMM EDI Server")))
                            {
                                if (name == currentRcvName)
                                {
                                    nameCounter++;
                                }
                                else
                                {
                                    if (rowCount > 0)
                                    {
                                        //  Recievers.Add(currentRcvName, nameCounter);//may not need this Hashtable
                                        export = sumRow + currentRcvName + "|" + nameCounter + Environment.NewLine +
                                                  Environment.NewLine;
                                        om.RowData.Add(export);
                                        export = Environment.NewLine + Environment.NewLine;
                                        om.RowData.Add(export);
                                    }
                                    export = "";
                                    nameCounter = 1;
                                    currentRcvName = name;
                                }
                                export += tempDateVendor;
                                export += name + "|";
                                #region comma checks
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                UOM = (dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim(); //changes UNIT02EA TO EA
                                export +=
                                    CommaCheck(UOM.Substring(UOM.Length - 2)) +   //UOM - changes UNIT02EA TO EA
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                UOM = (dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim();
                                export +=
                                    CommaCheck(UOM.Substring(UOM.Length - 2)) +    //UOM - changes UNIT02EA TO EA
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export +=
                                    CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim()) +
                                    "|";
                                export += CommaCheck((dsRcvRpt.Tables[0].Rows[rowCount].ItemArray[indx++].ToString()).Trim());
                                export += Environment.NewLine;
                                #endregion
                                //indx = 0;
                                //rowCount++;
                                om.RowData.Add(export);
                                //export = "";
                             }
                            indx = 0;
                            rowCount++;
                            export = "";
                        }
                        // Recievers.Add(currentRcvName, nameCounter);//may not need this Hashtable
                        //print the sum row for the last RCV_NAME
                        export = sumRow + currentRcvName + "|" + nameCounter; // + Environment.NewLine + Environment.NewLine;
                        om.RowData.Add(export);
                        

                        om.SendOutput();
                        //currentFileName += dtu.DateTimeCoded() + ".csv";
                        //File.WriteAllText(xportPath + currentFileName, export);
                    }
                    else
                    {
                        export = "Nothing to report";
                        om.SendOutput();
                        //currentFileName += dtu.DateTimeCoded() + ".csv";
                        //File.WriteAllText(xportPath + currentFileName, export);
                    }
                }
                else
                {
                    export = "Nothing to report";
                    om.SendOutput();
                    //currentFileName += dtu.DateTimeCoded() + ".csv";
                    //File.WriteAllText(xportPath + currentFileName, export);
                }

            }
            catch (Exception dbx) {
                //MsgBox.Error("LoadDataSet" + Environment.NewLine + Request.ConnectString +
                //                Environment.NewLine + dbx.Message.ToString(), "Database Error");
                lm.Write("LoadDataSet:    " + dbx.Message);

            }
        }
       
        private void GetStartEndTime(ref string start, ref string end) {
            string[] dateParts = dtu.DateTimeToShortDate(DateTime.Now).Split("/".ToCharArray());
            start = dateParts[2] + "-" + (dateParts[0].Length == 1 ? "0" : "") + dateParts[0] + "-" + (dateParts[1].Length == 1 ? "0" : "") + dateParts[1] + " 00:00:00.000";
            end = dateParts[2] + "-" + (dateParts[0].Length == 1 ? "0" : "") + dateParts[0] + "-" + (dateParts[1].Length == 1 ? "0" : "") + dateParts[1] + " 23:59:29.000";
            lm.Write("Start: " + start + TAB + "End: " + end);
        }

    }
}
