*匯入資料;
proc import out=mydata 
     datafile= "/home/u64061874/Findata_201420.xls"
     dbms=xls replace;
run;

/* 顯示變數格式*/
proc contents data=mydata;
run;

/*計算基本統計量*/
proc means data=mydata nmiss n mean median;
           var Current_Ratio Quick_Ratio;
run;

/*分群基本統計量用年分群*/
proc means data=mydata nmiss n mean median;
           var Current_Ratio Quick_Ratio;
           by year;
run;

/*分群基本統計量用年分群並排序*/
proc sort data=mydata;
          by year;
run;

/*資料處理*/
DATA mydata2;
set mydata;

/*文字轉數值型態*/
roa2 = roa + 0;
roe2 = input(roe, 8.);
cash_flow_ratios2 = input(cash_flow_ratios, 8.);
sales_growth_rate2 = input(sales_growth_rate, 8.);
ta_turnover2 = input(ta_turnover, 8.);
days_sales_outstnding2 = input(days_sales_outstnding, 8.);
inventory_turnover2 = input(inventory_turnover, 8.);
days_payable_outstanding2 = input(days_payable_outstanding, 8.);

/*刪除舊的欄位*/
drop roa roe cash_flow_ratios sales_growth_rate ta_turnover days_sales_outstnding inventory_turnover days_payable_outstanding;

/*重新命名新的欄位*/
rename roa2=roa roe2=roe cash_flow_ratios2=cash_flow_ratios sales_growth_rate2=sales_growth_rate ta_turnover2=ta_turnover days_sales_outstnding2=days_sales_outstnding inventory_turnover2=inventory_turnover days_payable_outstanding2=days_payable_outstanding;

/*進行加減乘除運算*/
v1 = cash_flow_ratios / days_payable_outstanding;

/*將缺失值(.)給刪除*/
if v1 = . or v1>10000000 or v1<-10000000 then delete;
if roa = . or roa = . or tobins_q = . then delete;

drop v1;

/*萃取字元 substr(變數名稱,開始字元,連續萃取幾個字元)
中文一個字母代表兩個位元*/
temp = substr(name, 1, 4);

/*取產業別*/
ind=int(Company/100);
run;

proc corr data=mydata2;
run;

/*線性回歸*/
proc reg data=mydata2;
	model roe=cash_flow_ratios sales_growth_rate current_ratio debt_ratio ta_turnover/vif selection=stepwise;
run;
	
data mydata2_1;
	set mydata2;
	keep name year company roe roa;
run;

data mydata2_2;
	set mydata2;
	keep company year cash_flow_ratios sales_growth_rate current_ratio debt_ratio ta_turnover;
	rename company=company2 year = year2;
run;

/*合併表格*/
proc sql;
create table mergedata1 as select e.*,s.*
from mydata2_1 as e
left join mydata2_2 as s
on e.company=s.company2 and (e.year-s.year2)=1;
quit;

proc sort data=mydata2;
	by ind;
run;

/*noprint表示不顯示在螢幕上，outest為一個為一個SAS檔案名，會把估計裡面會有係數放在在這個檔中
裡面會有r-square*/
proc reg data=mydata2 noprint outest=coef rsquare;
	model roe=cash_flow_ratios sales_growth_rate current_ratio debt_ratio ta_turnover/vif selection=stepwise;
	by ind;
run;

/*匯出excel檔*/
proc export data=coef outfile='/home/u64061874/coef.xls'
dbms= xls replace;
run;

proc sort data=mydata2;
	by year;
run;

/*用年分群，ods output parameterestimates =sas檔名 為另一種估計細節的方法
但這個方法不能跟noprint一起用*/
proc reg data=mydata2 outest=coef rsquare;
	model roe=cash_flow_ratios sales_growth_rate current_ratio debt_ratio ta_turnover/vif selection=stepwise;
	by year;
	ods output parameterestimates=parms;
run;

/*分群*/
proc sort data=mydata2;
	by year ind;
run;

/*計算產業roe和ta_turnover的每一個年度的中位數，在變數前加med_*/
proc means data=mydata2  ;
      var roe TA_turnover ;
	  by year ind;
	   output out=yrind_med (drop=_type_ _freq_)
        median=med_roe med_TA_turnover ; 
run;

data yrind_med;
   set yrind_med;
      rename year=year3 ind=ind3;
   run;


data yrind_med;
  set yrind_med;
  rename year=year3 ind=ind3;
run;

/*合併"產業平均中位數與原來財務資料檔*/
proc sql;
 create table mydata3
 as select e.*,s.*
 from mydata2 as e
 left join yrind_med  as s
 on e.year=s.year3
and ( e.ind - s.ind3)= 0;
quit;

/*產生虛擬變數，按照產業中位數分成高低兩群*/
data  mydata4;
   set mydata3;
      if roe >= med_roe then high_roe=1;
	     else high_roe=0;
      if  TA_turnover >= med_TA_turnover 
        then high_ta_turn=1;
	     else high_ta_turn=0;

		 drop year3 ind3 temp;
run;

proc delete data=mydata2_1 mydata2_2;
run;

/*羅吉斯回歸*/
/*output out 預測=1發生機率到sas檔案*/
/*decs表示y降冪排列*/
proc logistic data=mydata4 desc ;
    model high_roe= Cash_Flow_Ratios 
   sales_growth_rate Current_Ratio 
    Debt_Ratio  high_ta_turn 
  / selection=stepwise rsquare   ; 
  output out=estimates p=est_response;
run;

data estimates2;
   set estimates;
      if est_response >= 0.5 then pre_y=1;
	   else pre_y=0;
run;

/*混淆矩陣*/
 proc freq data=estimates2;
     tables pre_y*high_roe;
 run;

/*主成分分析(pca,principle component anaysis)*/
proc princomp data=mydata4 out=pca_result;
   var cash_flow_ratios current_ratio quick_ratio;
run;

/*因素分析(factor analysis)
如果發現結果和變數與兩個因素皆有關係，沒有靠邊站，則可以刪除*/
/*如果旋轉之後還是一樣的現象，刪除*/
proc factor data=mydata4 n=2 rotate=varimax out=factorout;
  var cash_flow_ratios current_ratio quick_ratio ta_turnover debt_ratio;
 run;
 
/*標準化變數*/
proc standard data=mydata4 mean=0 std=1 out=mydata4_st;
  var cash_flow_ratios current_ratio quick_ratio ta_turnover debt_ratio;
run;

/*CAPM*/
/*讀取股票資料檔*/
proc import out=stock
    datafile= "/home/u64061874/twstock.csv"
    dbms=csv replace;
run;

data stock2;
  set stock; 
   year=year(年月);
   month=month(年月);
   rename 證券代碼=id 簡稱=name 年月=date "報酬率％_月"n=ret "流通在外股數(千股)"n=num_sharesout "市值(百萬元)"n=cap;
   drop 年月;
run;

proc contents data=stock2;
run;

proc sort data=stock2;
  by id year month;
run;

/*將大盤報酬從股票資料檔萃取下來*/
data mktret;
  set stock2;
   if id = . ;
   keep year month ret cap;
   rename ret=mkt_ret  cap=mkt_cap;
 run;
 
/*把原來跟各股疊放在一起大盤拿掉*/
 data stock2;
   set stock2;
    if id=. then delete;
run;

/*再將大盤報酬率橫向與個股報酬合併*/
 proc sql;
 create table stock2_temp
 as select e.*,s.*
 from stock2  as e
 left join  mktret  as s
 on e.year=s.year and e.month=s.month;
quit;

/*先將目標公司與目標年度簡單萃取出來，之後方便股價合併*/
data target_capm;
  set stock2_temp ;
    keep id year month  ;
run;

data stock2_temp ;
 set stock2_temp ;
  rename id=id2 year=year2 month=month2;
 run;

 proc sql;
 create table stock2_temp2
 as select e.*,s.*
 from  target_capm as e
 left join   stock2_temp   as s
 on e.id=s.id2 and ( 1 <= ( ( 12*e.year +e.month ) - (12*s.year2 + s.month2 ) ) <= 12 ) ;
quit;

proc sort data=stock2_temp2 ;
 by id year month year2 month2;
run;

/*把合併沒有成功的刪掉*/
data stock2_capm ;
  set stock2_temp2 ;
    if id2=. then delete;
	drop id2;
run;

proc sort data=stock2_capm;
  by id year month;
run;

/*CAPM(滾動)-每個公司每年的的bata是用前12個月月報酬計算*/
proc reg data=stock2_capm noprint outest=capm ;
   model ret = mkt_ret;
      by id year month;
 run;
 quit;
 
 data capm2;
  set capm;
  test=1;
    keep id year month intercept mkt_ret test;
    rename intercept=alpha mkt_ret=beta;
run;
 
/*按bata高低分成三群，算各群的equal-weighted return*/
proc sort data=capm2;
    by year month beta;
run;

/*有一些特定分位沒法用proc means*/
proc univariate  data=capm2 noprint;
  var beta;
  output out=qtile
  pctlpts= 33 66 pctlpre=beta_pct;
  by year month;
run;

data qtile;
  set qtile;
    test=1;
 run;
 
/*合併同原來資料檔案
(因為共同欄位一樣，直接用sas內建合併merge指令)*/
/*要用merge合併前提是兩檔案共同欄位名稱相同，然後兩檔案也得按照共同欄位排好序才行*/
data target_capm2;
   merge capm2 qtile;
    by year month;
 run;

/*按照beta高低分三群bata_port*/
data target_capm2;
  set target_capm2;
      if beta <= beta_pct33 then beta_port=1 ;
      else if beta <= beta_pct66 then beta_port=2;
	  else beta_port=3;
	  drop test; 
run;

/*萃取個股報酬率*/
data reti_data;
  set stock2_capm;
    keep year month id ret;
run;

/*把有個股報酬率與bata的檔案合併*/
 proc sql;
 create table target_capm3
 as select e.*,s.*
 from reti_data  as e
 left join  target_capm2  as s
 on e.id=s.id and e.month=s.month and e.year=s.year;
quit;


proc sort  data=target_capm3;
  by  year month beta_port;
 run;
 

/*計算以bata高低分三群的porfilio 的equal-weighted-profolio bata*/
proc means  data=target_capm3 mean std noprint;
   var ret beta;
    by year month beta_port;
    output out=capm_Result (drop=_type_ _freq_)
        mean = mean_ret mean_bata std=std_ret std_bata;
run;