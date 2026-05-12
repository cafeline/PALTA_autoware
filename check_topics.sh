#!/bin/bash

# トピックリストのファイル名
TOPICS_FILE="topics.txt"

# ファイルの存在確認
if [ ! -f "$TOPICS_FILE" ]; then
    echo "エラー: '$TOPICS_FILE' が見つかりません。"
    exit 1
fi
source /home/hayatotokida/training/PALTA_autoware/install/setup.bash
echo "=========================================="
echo " ROS 2 トピックの出力状態を確認します"
echo "=========================================="

# 現在アクティブなトピック一覧を取得
ACTIVE_TOPICS=$(ros2 topic list)

# topics.txtを1行ずつ読み込む
while IFS= read -r topic || [ -n "$topic" ]; do
    # 空行をスキップし、前後の空白や連続するスラッシュを整形(// -> /)
    clean_topic=$(echo "$topic" | xargs | sed 's/\/\//\//g')
    if [ -z "$clean_topic" ]; then continue; fi

    # アクティブなトピック一覧に含まれているか確認
    if echo "$ACTIVE_TOPICS" | grep -qx "$clean_topic"; then
        echo -e "[\e[32m OK \e[0m] 出力あり: $clean_topic"
    else
        echo -e "[\e[31m NG \e[0m] 出力なし: $clean_topic"
    fi
done < "$TOPICS_FILE"

echo "=========================================="
echo " 確認が完了しました。"
