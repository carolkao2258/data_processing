/* ========== 0) 基本設定 ========== */
options notes stimer source nosyntaxcheck validvarname=V7;

%let home        = /home/&sysuserid;
%let sample_file = &home/sample_list.xlsx;        /* ← 你的 sample_list 檔 */
%let fin_file    = &home/financial_data.xlsx;     /* ← 你的 financial_data 檔 */
%let outdir      = &home;

/* 檔案存在檢查（避免路徑打錯就一路報錯） */
%macro must_exist(path);
  %if not %sysfunc(fileexist(&path)) %then %do;
    %put ERROR: File not found -> &path ;
    %abort cancel;
  %end;
%mend;
%must_exist(&sample_file);
%must_exist(&fin_file);

/* ========== 1) 以 PROC IMPORT 匯入（XLSX 預設取首列為欄名） ========== */
/* 提醒：若需要指定工作表，可加一行：sheet='工作表1'n; */
proc import out=sample_list 
     datafile="&sample_file" 
     dbms=xlsx replace;
run;

proc import out=financial_data 
     datafile="&fin_file" 
     dbms=xlsx replace;
run;

/* ========== 2) 合併基表（以 sample_list 為主；只挑 b 端所需欄位，避免重複鍵值） ========== */
proc sql;
  create table merge_all_base as
  select
      a.companyID, a.companyName, a.year,
      /* 只取 b 端的財務欄位，不取 b 的 companyID/companyName/year → 沒有重複欄位警告 */
      b.ROE, b.Equity, b.TA, b.ROA, b.ARTR, b.labor_cost,
      b.interest_income, b.interest_cost, b.brokerage_income,
      b.loan_income, b.lending_income, b.underwriting_income,
      b.stock_income, b.dividend_income, b.futures_income,
      b.securities_income, b.settlement_income, b.futures_management_income,
      b.management_fee_income, b.consulting_fee_income,
      b.margin_loans_receivable, b.current_ratio
  from sample_list as a
  left join financial_data as b
    on a.companyID = b.companyID
   and a.year      = b.year
  ;
quit;

/* ========== 3) 為財務欄位建立 *_n 數值版（去逗號、將 '-' 視為缺值） ========== */
%let numvars =
  ROE Equity TA ROA ARTR labor_cost
  interest_income interest_cost brokerage_income loan_income lending_income
  underwriting_income stock_income dividend_income futures_income
  securities_income settlement_income futures_management_income
  management_fee_income consulting_fee_income margin_loans_receivable
  current_ratio
;

data merge_all_num;             /* 保留原欄 + *_n 數值版 */
  set merge_all_base;

  length _c $64;
  %macro mk_numeric(vars);
    %local i v;
    %let i=1;
    %do %while(%scan(&vars,&i,%str( )) ne );
      %let v=%scan(&vars,&i,%str( ));
      length &v._n 8;
      _c = strip(vvalue(&v));          /* 不論原型別都先視為字串處理 */
      if _c = '-' then _c = '';        /* '-' 視為缺值 */
      _c = compress(_c, ', ');         /* 去千分位逗號與空白 */
      &v._n = input(_c, ?? best32.);   /* 轉數值；失敗→缺值（?? 抑制 NOTE） */
      %let i=%eval(&i+1);
    %end;
  %mend;
  %mk_numeric(&numvars)

  drop _c;
run;

/* ========== 4) 用 *_n 重建乾淨數值版 merge_all（欄名回覆原名）+ 計算 Leverage ========== */
proc sql;
  create table merge_all as
  select
    companyID,
    companyName,
    year,                                  /* 若 year 原本是字串，改 year_n as year */

    /* *_n → 原名（全部 numeric） */
    ROE_n  as ROE,
    Equity_n as Equity,
    TA_n  as TA,
    ROA_n as ROA,
    ARTR_n as ARTR,
    labor_cost_n as labor_cost,
    interest_income_n as interest_income,
    interest_cost_n as interest_cost,
    brokerage_income_n as brokerage_income,
    loan_income_n as loan_income,
    lending_income_n as lending_income,
    underwriting_income_n as underwriting_income,
    stock_income_n as stock_income,
    dividend_income_n as dividend_income,
    futures_income_n as futures_income,
    securities_income_n as securities_income,
    settlement_income_n as settlement_income,
    futures_management_income_n as futures_management_income,
    management_fee_income_n as management_fee_income,
    consulting_fee_income_n as consulting_fee_income,
    margin_loans_receivable_n as margin_loans_receivable,
    current_ratio_n as current_ratio,

    /* Leverage = TA / Equity（避開 0/缺值） */
    case when Equity_n is not null and Equity_n ne 0
         then TA_n / Equity_n
         else .
    end as Leverage
  from merge_all_num
  ;
quit;

/* ========== 5) 只刪回歸所需欄位缺值（保留樣本）+ 排序 ========== */
data merge_all;
  set merge_all;
  if cmiss(companyID) or missing(year) then delete; /* 鍵值必須存在 */
  /* Y+X 都要在才留下：ROE = f(current_ratio, underwriting_income, brokerage_income, ARTR, labor_cost) */
  if nmiss(ROE, current_ratio, underwriting_income, brokerage_income, ARTR, labor_cost) then delete;
run;

proc sort data=merge_all; 
     by companyID year; 
     run;

/* ========== 6) merge_partial（不刪缺值；同主表） ========== */
proc sql;
  create table merge_partial as
  select a.*,
         b.ROE, b.Equity, b.TA, b.ROA, b.ARTR, b.labor_cost
  from sample_list as a
  left join financial_data as b
    on a.companyID = b.companyID
   and a.year      = b.year
  ;
quit;

proc sort data=merge_partial; 
     by year companyID; 
     run;

/* ========== 7) 匯出 ========== */
proc export data=merge_all
     outfile="&outdir/merge_all.xlsx" 
     dbms=xlsx replace;
     sheet="merge_all"; 
     putnames=yes;
run;

proc export data=merge_partial
     outfile="&outdir/merge_partial.xlsx" 
     dbms=xlsx replace;
     sheet="merge_partial"; 
     putnames=yes;
run;

/* ========== 8) OLS 迴歸 + 報表/診斷輸出（帽子值用 h_lev，避免與 Leverage 混淆） ========== */
ods excel file="&outdir/reg_report.xlsx" options(sheet_interval='proc');
ods output ParameterEstimates = reg_params
           ANOVA              = reg_anova
           FitStatistics      = reg_fit
           CollinDiag         = reg_collin
;

proc reg data=merge_all;
  model ROE = current_ratio underwriting_income brokerage_income ARTR labor_cost
        / vif tol collin acov stb;
  output out=reg_out p=pred r=resid student=sr cookd=cookd h=h_lev;
run; quit;

ods excel close;

/* （可選）係數表另存 */
proc export data=reg_params 
     outfile="&outdir/reg_params.xlsx" 
     dbms=xlsx replace; 
     run;