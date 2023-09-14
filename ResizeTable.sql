set verify off
set feedback off
set recsep off;
set pagesize 0
Set linesize 200 
Set numwidth 30
spool /tmp/ResizeTable.out
select 'DBFILE:'||file_id||':'||file_name||':'||TO_CHAR(bytes/1024/1024) 
from      
(
select  bytes,file_id,file_name from dba_data_files where tablespace_name = '&1' order by bytes
) SmallDbfSize
;
--Select 'FIN SQL' 
--from dual
--;
select 'SIZE:'||TO_CHAR((BiggestDBFile.bytes*20)/100/1024/1024)
from
(
select bytes,row_number() over (order by bytes desc) rang
from dba_data_files where tablespace_name = '&1'
) BiggestDBFile
where rang = 1
;
select 'FS:'||file_name from dba_data_files;
spool off
exit;
