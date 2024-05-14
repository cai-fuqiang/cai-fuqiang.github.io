set -e
MAKE_PATCH2MD_SCRIPTS="make_patch_to_md.sh"

usage()
{
  echo main.sh [dir_path] [categories] [tags]
}

main()
{
  DIR_PATH=$1
  CATERGORIES=$2
  TAGS=$3
  SCRIPTS_PATH=`pwd`
  if [ ! -d "$DIR_PATH" ] || [ "$CATERGORIES" == "" ] || [ "$TAGS" == "" ];then
    usage
    exit 1
  fi

  cd $DIR_PATH

  for FILE_NAME in $(ls *.patch)
  do
    sh $SCRIPTS_PATH/$MAKE_PATCH2MD_SCRIPTS $FILE_NAME $CATERGORIES $TAGS
  done

  mkdir .patch_org
  mv *.patch .patch_org
  cd -
}

main $@
