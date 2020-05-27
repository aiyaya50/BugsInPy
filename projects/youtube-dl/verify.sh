#!/bin/bash
input="project.info"
githubURL=""
checkfurther="NO"
folder_location="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
project_location=""
temp_location=""
fail_number=0
pass_number=0
project_name=""
declare -a fail_list
declare -a pass_list

#check project info
echo $folder_location
while IFS= read -r line
do
  if [[ "$line" == "github_url="* ]]; then
     githubURL="$(cut -d'"' -f 2 <<< $line)"
     echo "$githubURL"
  elif [[ "$line" == 'status="OK"'* ]]; then
     checkfurther="YES"
     #clone project if status OK
     git clone "$githubURL"
  fi
  echo "$line"
done < "$input"
if [[ "$checkfurther" == "NO" ]]; then
  exit
fi

#get project name
dirs=($(find . -maxdepth 1 -type d))
for dir in "${dirs[@]}"; do
  if [[ "$dir" != "./bugs" && "$dir" != "." ]]; then
     var="$(cut -d'/' -f 2 <<< $dir)"
     project_location="$folder_location/$var"
     project_name=$var
  fi
done

#function for verifying bugs
my_function () {
  #read file run_test.sj
  run_command_all=""
  DONE=false
  until $DONE ;do
  read || DONE=true
  if [[ "$REPLY" != "" ]]; then
     run_command_all+="$REPLY;"
     echo $REPLY
  fi
  done < run_test.sh
  IFS=';' read -r -a run_command <<< "$run_command_all"
  echo "$run_command"
  
  #read bug.info file
  DONE=false
  until $DONE ;do
  read || DONE=true
  if [[ "$REPLY" == "buggy_commit_id"* ]]; then
       buggy_commit="$(cut -d'"' -f 2 <<< $REPLY)"
  elif [[ "$REPLY" == "fixed_commit_id"* ]]; then
       fix_commit="$(cut -d'"' -f 2 <<< $REPLY)"
  elif [[ "$REPLY" == "test_file"* ]]; then
       test_file_all="$(cut -d'"' -f 2 <<< $REPLY)"
       IFS=';' read -r -a test_file <<< "$test_file_all"
  fi
  done < bug.info

  echo "$buggy_commit"
  echo "$fix_commit"
  printf "%s\n" "${test_file[@]}"
  for index in "${!run_command[@]}"
  do
     echo ${run_command[index]}
  done
  
  #go to project location
  cd "$project_location"
  source env/bin/activate
  
  #reset to fix commit and install the requirement based on requirements.txt in bugs
  git reset --hard "$fix_commit"
  pip install -r "$temp_location/requirements.txt"

  #run every command on the run_test.sh
  run_command_filter=""
  for index in "${!run_command[@]}"
  do
  run_command_now=${run_command[index]}
  
  echo "RUN EVERY COMMAND"
  echo "$index"
  echo "$run_command_now"
  echo "$test_file_now"
  
  res_first=$($run_command_now 2>&1)
  #update list for command if running output OK and write on the fail if not
  echo "$res_first"
  if [[ ${res_first##*$'\n'} == *"OK"* || ${res_first##*$'\n'} == *"pass"* ]]; then
     run_command_filter+="$run_command_now;"
  else
     fail_list+=("$temp_location ($run_command_now)")
     fail_number=$(($fail_number + 1))
     echo "$run_command_now" &>>"$project_name-$var-fail.txt"
     echo "$res_first" &>>"$project_name-$var-fail.txt"
  fi
  done

  #copy test file from project to bugs folder
  for index in "${!test_file[@]}"
  do
     test_file_now=${test_file[index]}
     cp -v "$project_location/$test_file_now" "$temp_location"
  done

  #reset to buggy commit
  git reset --hard "$buggy_commit"
  
  #move test file from bugs folder to project
  for index in "${!test_file[@]}"
  do
     test_file_now=${test_file[index]}
     string1="${test_file_now%/*}"
     string2="${test_file_now##*/}"
     mv -f  "$temp_location/$string2" "$project_location/$string1"
  done

  #install the requirement from requirements.txt in bugs folder
  pip install -r "$temp_location/requirements.txt"
  
  #run every command that output ok from before
  IFS=';' read -r -a run_command_2 <<< "$run_command_filter"
  for index in "${!run_command_2[@]}"
  do
     run_command_now=${run_command_2[index]}
     res_second=$($run_command_now 2>&1)
     echo "$res_second"
     if [[ ${res_second##*$'\n'} == *"FAIL"* || ${res_second##*$'\n'} == *"error"* || ${res_second##*$'\n'} == *"fail"* ]]; then
         pass_list+=("$temp_location ($run_command_now)")
         pass_number=$(($pass_number + 1))
     else
         fail_list+=("$temp_location ($run_command_now)")
         fail_number=$(($fail_number + 1))
         echo "$run_command_now" &>>"$project_name-$var-fail.txt"
         echo "$res_first" &>>"$project_name-$var-fail.txt"       
     fi
  done
  
}

#go to project folder and activate the env
cd "$project_name"
pwd
python -m venv env
source env/bin/activate
cd ..
cd "bugs"
#loop for every bugs, calling funct.
dirs=($(find . -maxdepth 1 -type d))
for dir in "${dirs[@]}"; do
  if [[ "$dir" != "." ]]; then
     var="$(cut -d'/' -f 2 <<< $dir)"
     temp_location="$folder_location/bugs/$var"
     cd "$temp_location"
     pwd
     my_function
  fi
done
for dir in "${pass_list[@]}"; do
  echo "$dir"
done
cd "$folder_location"

#print fail and pass on the file txt
printf "%s\n" "${fail_list[@]}" > "$project_name-fail.txt"
printf "%s\n" "${pass_list[@]}" > "$project_name-pass.txt"

echo "PASS: $pass_number" &>>"$project_name-pass.txt"
echo "FAIL: $fail_number" &>>"$project_name-fail.txt" 
