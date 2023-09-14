set verify off
set feedback off
set recsep off;
set pagesize 0
spool /tmp/StateBase.out
SELECT INSTANCE_NAME, STATUS, DATABASE_STATUS FROM V$INSTANCE;
select tablespace_name, round(used_percent) from dba_tablespace_usage_metrics where tablespace_name = '&1';
spool off
exit;
