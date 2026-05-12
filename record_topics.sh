#!/bin/bash

# トピックリストのファイル名
TOPICS_FILE="topics.txt"

# ファイルの存在確認
if [ ! -f "$TOPICS_FILE" ]; then
    echo "エラー: '$TOPICS_FILE' が見つかりません。"
    exit 1
fi
source /home/hayatotokida/training/PALTA_autoware/install/setup.bash
# 記録対象のトピックを格納する変数
RECORD_TOPICS=""

# topics.txtを1行ずつ読み込んで変数に結合する
while IFS= read -r topic || [ -n "$topic" ]; do
    # 空行をスキップし、前後の空白や連続するスラッシュを整形
    clean_topic=$(echo "$topic" | xargs | sed 's/\/\//\//g')
    if [ -z "$clean_topic" ]; then continue; fi
    
    # スペース区切りで追加
    RECORD_TOPICS="$RECORD_TOPICS $clean_topic"
done < "$TOPICS_FILE"

# トピックが1つも抽出できなかった場合
if [ -z "$RECORD_TOPICS" ]; then
    echo "エラー: '$TOPICS_FILE' に有効なトピックが記載されていません。"
    exit 1
fi

echo "=========================================="
echo " 以下のトピックを ros2 bag record で記録します"
echo "=========================================="
for t in $RECORD_TOPICS; do
    echo " - $t"
done
echo "=========================================="
echo " 記録を終了するには Ctrl+C を押してください..."
echo ""

# ros2 bag record を実行
ros2 bag record $RECORD_TOPICS
