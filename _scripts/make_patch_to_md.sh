set -e
G_FILE_NAME_NEW=""
G_DATE_LINE_WHOLE=""
G_DATE_LINE=""
G_TITLE=""
G_FILE_NAME=$1
G_CATEGORIES=$2
G_TAGS=$3
get_date_line_whole()
{
  if [ "$G_DATE_LINE_WHOLE" == "" ];then
    G_DATE_LINE_WHOLE=`cat $G_FILE_NAME |grep 'Date:'|awk  '{$1=""; print $0}'`
  fi
  echo $G_DATE_LINE_WHOLE
}

get_date_line()
{
  if [ "$G_DATE_LINE" == "" ];then
    DATE_LINE_WHOLE=`get_date_line_whole $G_FILE_NAME`

    G_DATE_LINE=`date -d "$DATE_LINE_WHOLE" "+%Y-%m-%d"`
  fi
  echo $G_DATE_LINE
}

get_file_name()
{
  if [ "$G_FILE_NAME_NEW" == "" ];then
    FILE_NAME_WITHOUT_PATCH=${G_FILE_NAME%.patch}
  fi

  DATE_LINE=`get_date_line`
  G_FILE_NAME_NEW=${DATE_LINE}'-'${FILE_NAME_WITHOUT_PATCH}.md
  echo $G_FILE_NAME_NEW
}


get_title()
{
  if [ "$G_TITLE" == "" ];then
    G_TITLE=`cat $G_FILE_NAME|grep Subject |awk '{$1="";print$0}'`
    OTHER=`cat $G_FILE_NAME|grep -A1 Subject |sed -n '2p'`

    if [ "$OTHER" == "" ];then
      echo $G_TITLE
      return
    fi
    G_TITLE_OTHER=`echo $OTHER | sed 's/^\[\[:space\]\]*//'`

    if [ "$G_TITLE_OTHER" != "" ];then
      G_TITLE=${G_TITLE}" "${G_TITLE_OTHER}
    fi
  fi
  echo $G_TITLE
}

get_default()
{
  if [ "$G_CATEGORIES" == "" ];then
    G_CATEGORIES="default"
  fi
  if [ "$G_TAGS" == "" ];then
    G_TAGS="default"
  fi
}

main()
{
  if [ "$G_FILE_NAME" == "" ];then
    echo please set file_name_\$1!!
    exit
  fi

  FILE_NAME_NEW=`get_file_name`

  DATE_LINE_WHOLE=`get_date_line_whole`

  TITLE=`get_title`

  get_default

#---
#layout: post
#title:  "[PATCH] KVM: Allow not-present guest page faults to bypass kvm"
#author: fuqiang
#date:   2007-09-17 18:58:32 +0200
#categories: [kvm]
#tags: [kvm]
#---

cat <<EOF > $FILE_NAME_NEW
---
layout:     post
title:      "$TITLE"
author:     "fuqiang"
date:       "$DATE_LINE_WHOLE"
categories: [$G_CATEGORIES]
tags:       [$G_TAGS]
---

\`\`\`diff
EOF

cat $G_FILE_NAME >> $FILE_NAME_NEW

echo \`\`\` >> $FILE_NAME_NEW
}

main
