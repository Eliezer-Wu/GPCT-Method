%macro GPCT(_DATSRC =, _STRATUM =, _X =, _Y =, _TREND = , _ALPHA = 0.05);

%if %bquote(%upcase(&_TREND.)) eq %str(ODDS) %then %do;
%end;
%else %if %bquote(%upcase(&_TREND.)) eq %str(RATIO) %then %do;
%end;
%else %do;
    %put %str(WAR)NING: _TREND takes value as odds or ratio. Macro stop.;
    %return;
%end;

%if %bquote(&_STRATUM.) eq %str() %then %do;
    %let VAR_KEEP = _STRATUM &_X. &_Y.;
%end;
%else %do;
    %let VAR_KEEP = &_STRATUM. &_X. &_Y.;
%end;

%macro SQLCond(_VarList =, _deli = %str( ), _left = , _right =, _out =);
%local COND i;
%do i = 1 %to %sysfunc(countw(&_VarList., "&_deli."));

    %let ELEMENT = %upcase(%scan(&_VarList., &i, "&_deli."));

    %if %length(&COND) %then %do;
        %let COND = &COND and &_left..&ELEMENT. = &_right..&ELEMENT.;
    %end;
    %else %do;
        %let COND = &_left..&ELEMENT. =  &_right..&ELEMENT.;
    %end;

%end;
%let &_out = &COND;
%mend SQLCond;

%macro SQLSelect(_VarList =, _deli = %str( ), _prefix =, _out =);
%local COND i;
%do i = 1 %to %sysfunc(countw(&_VarList., "&_deli."));

    %let ELEMENT = %upcase(%scan(&_VarList., &i, "&_deli."));
    %if %length(&COND) %then %do;
        %let COND = &COND, &_prefix..&ELEMENT.;
    %end;
    %else %do;
        %let COND = &_prefix..&ELEMENT.;
    %end;
%end;
%let &_out = &COND;
%mend SQLSelect;


data _GPCT_data;
    set &_DATSRC.;
%if %bquote(&_STRATUM.) eq %str() %then %do;
    _STRATUM = 1;
%end;
run;


%if %bquote(&_STRATUM.) eq %str() %then %do;
    %let _STRATUM = _STRATUM;
%end;

%let VAR_KEEP_SQL = %sysfunc(tranwrd(&VAR_KEEP., %str( ), %str(, )));
%let _STRATUM_SQL = %sysfunc(tranwrd(&_STRATUM., %str( ), %str(, )));
%local _STRATUM_SQL_a   ; %SQLSelect(_VarList = &_STRATUM., _deli = %str( ), _prefix =a           , _out = _STRATUM_SQL_a   );
%local _STRATUM_SQL_b   ; %SQLSelect(_VarList = &_STRATUM., _deli = %str( ), _prefix =b           , _out = _STRATUM_SQL_b   );
%local _STRATUM_SQL_COND; %SQLCond  (_VarList = &_STRATUM., _deli = %str( ), _left = a, _right = b, _out = _STRATUM_SQL_COND);
%put &VAR_KEEP.;
%put &VAR_KEEP_SQL.;
%put &_STRATUM.;
%put &_STRATUM_SQL.;
%put &_STRATUM_SQL_a.;
%put &_STRATUM_SQL_b.;
%put &_STRATUM_SQL_COND.;




proc sql noprint;
    create table _GPCT01 as
    select *, count(*) as _P, monotonic() as ID
    from _GPCT_data(keep = &VAR_KEEP.)
    group by &VAR_KEEP_SQL.
    ;
quit;

proc sql noprint;
    create table _P_SUM as
    select &_STRATUM_SQL., sum(_P) as P_SUM
    from _GPCT01
    group by &_STRATUM_SQL.
    ;
quit;

proc sql noprint;
    create table _GPCT02 as
    select &_STRATUM_SQL_a., a.&_X. as Xi, a.&_Y. as Yi, a._P as Pi, b.&_X. as Xj, b.&_Y. as Yj, b._p as Pj
    from _GPCT01 a, _GPCT01 b
    where &_STRATUM_SQL_COND.
    ;
quit;

data _GPCT03;
    set _GPCT02;
    K = ifn(Yi < Yj, -1, ifn(Yi > Yj, 1, 0));
    L = ifn(Xi < Xj, -1, ifn(Xi > Xj, 1, .));
    KL = K * L;
    _Rsi = ifn(KL =  1, Pj, 0);
    _Rdi = ifn(KL = -1, Pj, 0);
    _Rti = ifn(KL =  0, Pj, 0);
run;

proc sql noprint;
    create table _GPCT04 as
    select &_STRATUM_SQL., Xi, Yi, Pi, sum(_Rsi) as _Rsi_SUM, sum(_Rdi) as _Rdi_SUM, sum(_Rti) as _Rti_SUM
    from _GPCT03
    group by &_STRATUM_SQL., Xi, Yi, Pi
    ;
quit;

proc sql noprint;
    create table _GPCT05 as
    select a.*, b.P_SUM
    from _GPCT04 a left join _P_SUM b
    on &_STRATUM_SQL_COND.
    ;
quit;

proc sql noprint;
    create table _GPCT06 as
    select &_STRATUM_SQL., Xi, Yi, Pi, P_SUM, _Rsi_SUM / P_SUM as Rsi_PRE, _Rdi_SUM / P_SUM as Rdi_PRE, _Rti_SUM / P_SUM as Rti
    from _GPCT05
    ;
quit;

proc sql noprint;
    create table _GPCT07 as
    %if %upcase(&_TREND.) = ODDS %then %do;
    select &_STRATUM_SQL., Xi, Yi, Pi, P_SUM, Rsi_PRE + Rti / 2 as Rsi, Rdi_PRE + Rti / 2 as Rdi, Rti
    %end;
    %else %if %upcase(&_TREND.) = RATIO %then %do;
    select &_STRATUM_SQL., Xi, Yi, Pi, P_SUM, Rsi_PRE as Rsi, Rdi_PRE as Rdi, Rti
    %end;
    from _GPCT06 a
    ;
quit;

*** Point Esitmate ***;
proc sql noprint;
    create table _GPCT08_PE as
    select &_STRATUM_SQL., sum(Rsi * Pi) / P_SUM as Pc, sum(Rdi * Pi) / P_SUM as Pd, calculated Pc / calculated Pd as GPCT
    from _GPCT07
    group by &_STRATUM_SQL., P_SUM
    ;
quit;
*** done ***;

*** SE(GPCT) ***;
proc sql noprint;
    create table _GPCT09 as
    select a.*, b.Pc, b.Pd, b.GPCT
    from _GPCT07 a left join _GPCT08_PE b
    on &_STRATUM_SQL_COND.
    ;
quit;

proc sql noprint;
    create table _GPCT10 as
    select &_STRATUM_SQL., sqrt(sum((GPCT * Rdi - Rsi)**2 * Pi / P_SUM) / P_SUM) * 2 / Pd as GPCT_SE
    from _GPCT09
    group by &_STRATUM_SQL., Pd, P_SUM
    ;
quit;

proc sql noprint;
    create table _GPCT11_SE as
    select a.*, b.GPCT_SE
    from _GPCT08_PE a left join _GPCT10 b
    on &_STRATUM_SQL_COND.
    ;
quit;
*** done ***;

*** test Ho: GPCT = 1 ***;
    *** ln(GPCT) is normally distributed with SE(ln(GPCT)) = SE(GPCT) / GPCT ***;
    *** test H0: ln(GPCT) = 0 ***;
data _GPCT12;
    set _GPCT11_SE;
    ln_GPCT = log(GPCT);
    ln_GPCT_SE = GPCT_SE / GPCT;
    ln_GPCT_LCI = ln_GPCT + (probit(  (&_ALPHA. / 2)) * ln_GPCT_SE);
    ln_GPCT_UCI = ln_GPCT + (probit(1-(&_ALPHA. / 2)) * ln_GPCT_SE);
    GPCT_LCI = exp(ln_GPCT_LCI);
    GPCT_UCI = exp(ln_GPCT_UCI);
    PVALUE = 2 * (1 - cdf("NORMAL", abs(ln_GPCT / ln_GPCT_SE)));
run;
*** done ***;

*** overall test as section 3.2: H0: GPCT_1 = GPCT_2 = ... = GPCT_M ***;

data _GPCT_STR01;
    set _GPCT12;
    GPCT_STR_NUME_PRE = ln_GPCT / (ln_GPCT_SE)**2;
    GPCT_STR_DENO_PRE = 1 / (ln_GPCT_SE)**2;
run;
proc sql noprint;
    create table _GPCT_STR02 as
    select *, sum(GPCT_STR_NUME_PRE) as NUME_PRE, sum(GPCT_STR_DENO_PRE) as DENO_PRE
    from _GPCT_STR01
    ;
quit;
data _GPCT_STR03;
    set _GPCT_STR02;
    ln_GPCT_POOL = NUME_PRE / DENO_PRE;
run;

data _GPCT_STR04;
    set _GPCT_STR03;
    V_PRE = (ln_GPCT - ln_GPCT_POOL)**2 / ln_GPCT_SE**2;
run;

proc sql noprint;
    create table _GPCT_STR05 as
    select sum(V_PRE) as V, count(*) - 1 as DF, (1 - cdf("CHISQUARE", calculated V, calculated DF)) as PVALUE
    from _GPCT_STR04
    ;
quit;

*** done ***;

data GPCT;
    set _GPCT12;
%if %bquote(&_STRATUM.) eq _STRATUM %then %do;
    keep Pc Pd GPCT GPCT_SE GPCT_LCI GPCT_UCI PVALUE;
%end;
%else %do;
    keep &_STRATUM. Pc Pd GPCT GPCT_SE GPCT_LCI GPCT_UCI PVALUE;
%end;
run;

data GPCT_OVERALL_TEST;
    set _GPCT_STR05;
run;

proc datasets library = work memtype = data nolist;
    delete _GPCT: _P_SUM;
run; quit;
*** done ***;

%mend GPCT;
