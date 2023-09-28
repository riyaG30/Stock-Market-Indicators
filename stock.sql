WITH A AS (SELECT SYMBOL,DATE,[CLOSE],LAG([CLOSE],1) OVER(PARTITION BY SYMBOL ORDER BY SYMBOL,DATE) AS NUM,VOLUME,
[12 EMA],[26 EMA], MACD,[Signal Line]
FROM NIFTY)
--A and B tables to calc change %
,B AS (SELECT SYMBOL,DATE,[CLOSE],ROW_NUMBER() OVER(PARTITION BY SYMBOL ORDER BY SYMBOL,DATE) AS ROWNUM,
CASE WHEN ROW_NUMBER() OVER(PARTITION BY SYMBOL ORDER BY SYMBOL,DATE)>1 THEN 
([CLOSE]-NUM)/NUM *100 
ELSE 0
END AS [CHG%],
VOLUME,[12 EMA],[26 EMA], MACD,[Signal Line]
FROM A)

,VTABLE AS (SELECT *, 
CASE WHEN ROWNUM>=20 THEN 
AVG(VOLUME) OVER (PARTITION BY SYMBOL ORDER BY ROWNUM ROWS 20 PRECEDING)
ELSE 0
END AS [20DAVGVOLUME]
FROM B)
-- 20 d Avg Vol

,GAINTABLE AS (SELECT *,  
SUM(CASE WHEN [CHG%] > 0 THEN [CHG%] ELSE 0 END) 
OVER (PARTITION BY SYMBOL ORDER BY ROWNUM ROWS 14 PRECEDING)
/SUM(CASE WHEN [CHG%] > 0 THEN 1 ELSE NULL END)
OVER (PARTITION BY SYMBOL ORDER BY ROWNUM ROWS 14 PRECEDING) 
AS AVGGAIN,

ABS(SUM(CASE WHEN [CHG%] < 0 THEN [CHG%] ELSE 0 END)
OVER (PARTITION BY SYMBOL ORDER BY ROWNUM ROWS 14 PRECEDING)
/SUM(CASE WHEN [CHG%] < 0 THEN 1 ELSE NULL END)
OVER (PARTITION BY SYMBOL ORDER BY ROWNUM ROWS 14 PRECEDING)) 
AS AVGLOSS 

FROM B)
--Getting RS for RSI
,RSITABLE AS (SELECT *,
(100-(100/(1+[AVGGAIN]/[AVGLOSS]))) AS RSI 
FROM GAINTABLE)
-- Calculating RSI

,FIVEAVGTABLE AS (SELECT *,
CASE WHEN ROWNUM>=5 THEN 
AVG([CLOSE]) OVER (PARTITION BY SYMBOL ORDER BY ROWNUM ROWS 5 PRECEDING)
ELSE 0
END AS [5 DMA]
FROM B)
--5 DMA

,TWENTYAVGTABLE AS (SELECT *,
CASE WHEN ROWNUM>=20 THEN 
AVG([CLOSE]) OVER (PARTITION BY SYMBOL ORDER BY ROWNUM ROWS 20 PRECEDING)
ELSE 0
END AS [20 DMA]
FROM B)
-- 20 DMA

,DMATABLE AS (SELECT FIVEAVGTABLE.Symbol,FIVEAVGTABLE.Date,FIVEAVGTABLE.[Close],FIVEAVGTABLE.[CHG%],
FIVEAVGTABLE.ROWNUM,VTABLE.VOLUME,[20DAVGVOLUME],[5 DMA],[20 DMA],FIVEAVGTABLE.[12 EMA],
FIVEAVGTABLE.[26 EMA], FIVEAVGTABLE.MACD,FIVEAVGTABLE.[Signal Line],
CASE WHEN [5 DMA]!=0 AND [20 DMA]!=0 THEN 
CASE WHEN [5 DMA]>=[20 DMA] THEN 
'BULLISH'
ELSE 'BEARISH'
END
END AS DMAINDICATOR
FROM FIVEAVGTABLE
JOIN VTABLE ON VTABLE.SYMBOL=FIVEAVGTABLE.SYMBOL AND VTABLE.DATE=FIVEAVGTABLE.DATE 
JOIN TWENTYAVGTABLE ON FIVEAVGTABLE.SYMBOL=TWENTYAVGTABLE.SYMBOL AND FIVEAVGTABLE.DATE=TWENTYAVGTABLE.Date)

--Joined all the tables into one, and built indicators according to 5 DMA and 20 DMA

,D AS (SELECT DMATABLE.*,
LEAD(DMATABLE.[CHG%],1) OVER (PARTITION BY DMATABLE.SYMBOL ORDER BY DMATABLE.ROWNUM) AS NEXTDAYCLOSING,
CASE WHEN DMATABLE.ROWNUM<14 THEN 0
ELSE RSI 
END AS RSI
FROM DMATABLE
JOIN RSITABLE ON RSITABLE.SYMBOL=DMATABLE.SYMBOL AND RSITABLE.DATE=DMATABLE.DATE
)
--Nextdayclosing to find the relation b/w indicator and chg%


,RSIINDICATORTABLE AS (SELECT ROWNUM,SYMBOL,DATE,[CLOSE],[CHG%],VOLUME,[20DAVGVOLUME],
[5 DMA],[20 DMA],RSI,NEXTDAYCLOSING,DMAINDICATOR,[12 EMA],[26 EMA], MACD,[Signal Line],

CASE WHEN RSI>75 THEN 'OVERBOUGHT'
WHEN RSI BETWEEN 55 AND 75 THEN 'BULLISH'
WHEN RSI BETWEEN 45 AND 55 THEN 'NEUTRAL'
WHEN RSI BETWEEN 25 AND 45 THEN 'BEARISH'
WHEN RSI BETWEEN 1 AND 25 THEN 'OVERSOLD'
END AS RSIINDICATOR
FROM D)
-- Building indicator based on RSI values

,E AS (SELECT *,
CASE WHEN MACD>=[Signal Line]
THEN 'BULLISH'
ELSE 'BEARISH'
END AS MACDINDICATOR
FROM RSIINDICATORTABLE
WHERE NEXTDAYCLOSING IS NOT NULL 
AND ROWNUM>=34)
-- Building indicator based on MACD

,SUCCESSRATETABLE AS (SELECT *,
CASE WHEN DMAINDICATOR='BULLISH' AND RSIINDICATOR='BULLISH' AND MACDINDICATOR='BULLISH' AND
VOLUME>[20DAVGVOLUME] AND NEXTDAYCLOSING>=0
OR DMAINDICATOR='BEARISH' AND RSIINDICATOR='BEARISH' AND MACDINDICATOR='BEARISH' AND
VOLUME>[20DAVGVOLUME] AND NEXTDAYCLOSING<0
THEN 'SUCCESS'
WHEN DMAINDICATOR='BULLISH' AND RSIINDICATOR='BULLISH' AND MACDINDICATOR='BULLISH' AND
VOLUME>[20DAVGVOLUME] AND NEXTDAYCLOSING<0
OR DMAINDICATOR='BEARISH' AND RSIINDICATOR='BEARISH' AND MACDINDICATOR='BEARISH' AND 
VOLUME>[20DAVGVOLUME] AND NEXTDAYCLOSING>=0
THEN 'FAILURE'
END AS RESULT
FROM E)
-- Checking indicators' accuracy 

SELECT SYMBOL,DATE,[Close],[CHG%],VOLUME,[20DAVGVOLUME],[5 DMA],[20 DMA],
RSI,[12 EMA],[26 EMA],MACD,[Signal Line],DMAINDICATOR,RSIINDICATOR,MACDINDICATOR
FROM SUCCESSRATETABLE
WHERE NEXTDAYCLOSING IS NOT NULL
ORDER BY SYMBOL,ROWNUM
-- Getting the final table		
