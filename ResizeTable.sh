#!/bin/bash
# set oracle environment
export LANG=C
ORA_SID=$1
ORA_ENV=oraenv${ORA_SID}
ORA_TABLE=$2

State()
{
  # test base state
  STATE=$(su - oracle -c "ORACLE_SID=$ORA_SID && . $ORA_ENV &&
  sqlplus -s /nolog <<EOF
  connect / as sysdba
  @/tmp/StateBase.sql $ORA_TABLE
  exit
EOF
  ")
  
  # error if database not open
  if [ $( grep -q OPEN /tmp/StateBase.out ; echo $?) -ne 0 ]
  then
          echo "ERROR : DATABASE not OPEN : $STATE"
          rm -f /tmp/StateBase.out
          exit 1
  fi
  
  if [ $(  grep -q $ORA_TABLE /tmp/StateBase.out ; echo $?) -ne 0 ]
  then
          echo "tablespace $ORA_TABLE doesn t exit in $ORA_SID"
          exit 1
  fi
  
  # quit it %used is not >80%
  percent=$(grep $ORA_TABLE /tmp/StateBase.out | awk '{print $2}')
  if [ ${percent} -lt 80 ]
  then
          echo "Percent used for tablespace $ORA_TABLE is ${percent}% (less than 80%)"
          rm -f /tmp/StateBase.out
          exit 0
  fi
  rm -f /tmp/StateBase.out
}


Check_percent()
{
  # test base state
  STATE=$(su - oracle -c "ORACLE_SID=$ORA_SID && . $ORA_ENV &&
  sqlplus -s /nolog <<EOF
  connect / as sysdba
  @/tmp/StateBase.sql $ORA_TABLE
  exit
EOF
  ")
  percent=$(grep $ORA_TABLE /tmp/StateBase.out | awk '{print $2}')
  rm -f /tmp/StateBase.out
  echo "Percent used for tablespace $ORA_TABLE is ${percent}%"
}
  

Extend_tb()
{
  # check size
  result=$(su - oracle -c "ORACLE_SID=$ORA_SID && . $ORA_ENV &&
  sqlplus -s /nolog <<EOF
  connect / as sysdba
  @/tmp/ResizeTable.sql $ORA_TABLE
  exit
EOF
  ")
  if [ -z "$result" ]
  then
          echo "tablespace $ORA_TABLE doesn t exit in $ORA_SID"
          exit 1
  fi
  file=($(awk -F':' '/DBFILE/ {print $3}' /tmp/ResizeTable.out))
  size=($(awk -F':' '/DBFILE/ {print $4}' /tmp/ResizeTable.out| sed -e 's/\.[0-9]*//')) # integer only
  extend=($(awk -F':' '/SIZE/ {print $2}' /tmp/ResizeTable.out | sed -e 's/\.[0-9]*//')) # integer only
  FS=$(awk -F':' '/FS/ {print $2}' /tmp/ResizeTable.out )
  trueextend=$extend
  #extend=8332650
  # test if one datafile can be extended
  resize=0
  i=0
  while [ $i -lt ${#file[@]} ]
  do
  echo "tablespace $ORA_TABLE : datafile ${file[$i]} has a size of ${size[$i]} Mo"
  #verif taille FS
  free=$(echo "$(df -P ${file[$i]} | tail -1 | awk '{print $4}')/1024" | bc)
  echo "Size available in FS of tablespace is $free Mo"
  if [ $free -lt $extend ]
  then
          echo "FS of datafile ${file[$i]} is too small to resize it (less than $extend Mo)"
          resize=1
  else
          echo "FS of datafile ${file[$i]} is large enough to resize it"
          raise=$(echo "$size+$extend" | bc)
          echo "extend datafile of 20% of the bigest datafile"
          su - oracle -c "ORACLE_SID=$ORA_SID && . $ORA_ENV && sqlplus -s /nolog <<EOF
  connect / as sysdba
  alter database datafile '${file[$i]}' resize ${raise}M;
  exit
EOF" >> /tmp/sql.$$
          echo SQL output
          output=$(grep -v '*' /tmp/sql.$$) # put on one line
          rm -f /tmp/sql.$$
          echo $output | grep -i error
          [[ $? -eq 0 ]] &&  exit 1
          echo is ok
          echo "datafile ${file[$i]} resized to ${raise}Mo"
          resize=0
          rm -f /tmp/ResizeTable.out
  #        exit $resize
  	return 3
  fi
  (( i = $i + 1 ))
  done
  echo "No datafile had been extended"
}


Add_tb()
{
  # look for FS where we can create new datafile
  liste_FS=""
  for fs in $FS
  do
          new=$(df  --output=target  $fs | grep -v Mounted)
          if [ $(echo $liste_FS |grep -qw $new; echo $?) -ne 0 ]
          then
                  liste_FS="$liste_FS $new"
          fi
  done
  # suppress from list FS already tested
  i=0
  while [ $i -lt ${#file[@]} ]
  do
          DONE=$(df  --output=target ${file[$i]}| grep -v Mounted)
          if [ $(echo $liste_FS |grep -qw $new; echo $?) -eq 0 ]
          then
                  liste_FS=$(echo $liste_FS | sed -e "s#$DONE##")
          fi
          (( i = $i + 1 ))
  done
  # create datafile same size as the smallest datafile
  echo "find if other FS available : $liste_FS"
  create=0
  for fs in $liste_FS
  do
          free=$(echo "$(df -P $fs | tail -1 | awk '{print $4}')/1024" | bc)
          echo "Size available in FS $fs is $free Mo"
          if [ $free -lt ${size[0]} ]
          then
                  echo "FS $fs is too small (less than ${size[0]} Mo)"
                  create=1
          else
                  echo "FS $fs has enough free space"
                  # find highest indice rank for datafile
                  highest=0
                  for j in  ${file[@]}
                  do
                          indice=$(basename $j | sed -e 's/.*\([0-9]\).dbf/\1/')
                          [[ "$indice" -gt $highest ]] && highest=$indice
                  done
                  (( highest = $highest + 1 ))
                  oldfs=$(df  --output=target ${file[0]}| grep -v Mounted)
                  new=$(echo  ${file[0]} | sed -e "s#$oldfs#$fs#" | sed -e "s/[0-9].dbf/$highest.dbf/")
                  su - oracle -c "ORACLE_SID=$ORA_SID && . $ORA_ENV && sqlplus -s /nolog <<EOF
  connect / as sysdba
  alter tablespace $ORA_TABLE add datafile '$new' size ${size[0]}M;
EOF" >> /tmp/sql.$$
                  #echo "alter database datafile $new size ${size[0]}Mo"
                  echo SQL output
                  output=$(grep -v '*' /tmp/sql.$$) # put on one line
                  rm -f /tmp/sql.$$
                  echo $output | grep -i error
                  [[ $? -eq 0 ]] &&  exit 1
                  echo is ok
                  echo "added datafile $new of ${size[0]}Mo to tablespace $ORA_TABLE"
                  create=0
                  rm -f /tmp/ResizeTable.out
#                  exit $create
                  return $create
          fi
  done
  echo "no datafile created"
  exit 1
}

# main
State

Check_percent

while [ $percent -ge 80 ]
do
   Extend_tb
   if [ $? -ne 3 ]
   then
	Add_tb
   fi
   rm -f /tmp/ResizeTable.out
   Check_percent
done
