*匯入資料1;
proc import out=data1 
     datafile= '/home/u64061874/data1.xlsx'
     dbms=xlsx replace;
run;

/*資料處理*/
DATA data3;
    set data1;

    underwriting_ratio = underwriting_revenue / TA;
    brokerage_ratio = brokerage_revenue / TA;
    drop O P Q R S T U V W X Y Z AA	AB AC AD AE	AF AG AH AI AJ AK AL AM	AN AO AP AQ	AR;
    
/* 刪除缺失值 */
if underwriting_ratio = . then delete;
if brokerage_ratio = . then delete;
if TA = . then delete;
if size = . then delete;
if liquid_ratio = . then delete;
if Operating_Expense_Ratio = . then delete;
if Cash_Flow_Ratio = . then delete;
if GDP = . then delete;
if TA = . then delete;
if netprofit_growth = . then delete;
run;

/*顯示data3*/
proc print DATA=data3;
run;

*匯入資料2;
proc import out=data2 
     datafile= '/home/u64061874/data2.xlsx'
     dbms=xlsx replace;
run;

/*資料處理*/
DATA data4;
    set data2;
    
/* 刪除缺失值 */
if TA_turnover = . then delete;
if AR_turnover = . then delete;
run;

/*顯示data4*/
proc print DATA=data4;
run;

proc sort data=data3;
	by year;
run;

proc sort data=data4;
	by year;
run;

/*合併表格*/
proc sql;
create table data5 as select e.*,s.*
from data3 as e
left join data4 as s
on e.company=s.company and (e.year-s.year)=1;
quit;
run;

/*顯示data5*/
proc print DATA=data5;
run;

proc sort data=data5;
     by year;
run;

/*計算統計量*/
proc means data = data5;
by year;
run;

/*相關性*/
proc corr data=data5;
run;

/*主成分分析*/
proc princomp data=data5 out=pca_result;
   var size liquid_ratio Operating_Expense_Ratio Cash_Flow_Ratio GDP PAC netprofit_growth TA_turnover AR_turnover underwriting_ratio brokerage_ratio;
run;

/*匯出pca_result檔*/
proc export data=pca_result outfile='/home/u64061874/pca_result.xls'
dbms= xls replace;
run;

/*匯出data5檔*/
proc export data=data5 outfile='/home/u64061874/data5.xls'
dbms= xls replace;
run;