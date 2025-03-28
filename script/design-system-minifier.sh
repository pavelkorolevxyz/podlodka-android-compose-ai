#!/bin/bash

# Находим корневую директорию проекта (где находится директория .git)
find_project_root() {
    local current_dir="$PWD"
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    echo "Error: Not a git repository" >&2
    exit 1
}

PROJECT_ROOT=$(find_project_root)
COMPONENTS_PATH="$PROJECT_ROOT/design-system/src/main/designsystem/component"
OUTPUT_DIR="$PROJECT_ROOT/script/output"
mkdir -p "$OUTPUT_DIR"
COMPONENTS_OUTPUT_FILE="$OUTPUT_DIR/design_system_components.xml"

# Начинаем создавать XML файл
echo "<components>" > "$COMPONENTS_OUTPUT_FILE"

# Функция для извлечения сигнатур @Composable функций из файла
extract_components() {
    local file="$1"
    local filename=$(basename "$file")
    echo "Processing file: $file"

    # Извлекаем package из файла
    local package_line=$(grep -m 1 "^package" "$file")

    # Если пакет не найден, пропускаем файл
    if [ -z "$package_line" ]; then
        echo "No package declaration found in $file, skipping"
        return
    fi

    # Открываем компонент для файла
    echo "  <component>" >> "$COMPONENTS_OUTPUT_FILE"
    echo "$package_line" >> "$COMPONENTS_OUTPUT_FILE"
    echo "" >> "$COMPONENTS_OUTPUT_FILE"

    # Флаг для отслеживания добавления элементов в компонент
    local has_content=false

    # Хранение уже добавленных функций для избежания дублирования
    local added_functions=()

    # Обрабатываем @Composable функции
    grep -n "@Composable" "$file" | while read -r composable_line_info; do
        # Извлекаем номер строки
        local composable_line_num=$(echo "$composable_line_info" | cut -d':' -f1)

        # Проверяем, не является ли это Preview функцией
        local prev_line_num=$((composable_line_num - 1))
        local prev_line=$(sed -n "${prev_line_num}p" "$file")
        if [[ "$prev_line" == *"@Preview"* ]]; then
            continue
        fi

        # Ищем следующую строку с "fun"
        local fun_line_num=$(tail -n +$((composable_line_num+1)) "$file" | grep -n "fun " | head -1 | cut -d':' -f1)

        if [ -z "$fun_line_num" ]; then
            echo "No function declaration found after @Composable at line $composable_line_num"
            continue
        fi

        # Вычисляем абсолютный номер строки с "fun"
        local fun_line_num=$((composable_line_num + fun_line_num))

        # Извлекаем первую строку сигнатуры функции
        local fun_first_line=$(sed -n "${fun_line_num}p" "$file")

        # Пропускаем Preview функции
        if [[ "$fun_first_line" == *"Preview"* ]]; then
            continue
        fi

        # Извлекаем имя функции
        local fun_name=$(echo "$fun_first_line" | sed -n 's/.*fun \([a-zA-Z0-9_]*\).*/\1/p')

        # Проверяем, была ли уже добавлена эта функция
        local is_duplicate=false
        for added_function in "${added_functions[@]}"; do
            if [[ "$added_function" == "$fun_name" ]]; then
                is_duplicate=true
                echo "Skipping duplicate function: $fun_name"
                break
            fi
        done

        if [ "$is_duplicate" = true ]; then
            continue
        fi

        # Добавляем имя функции в список уже добавленных
        added_functions+=("$fun_name")

        # Если сигнатура заканчивается на скобку и фигурную скобку, значит, она однострочная
        if [[ "$fun_first_line" == *")"*"{"* ]]; then
            # Заменяем фигурную скобку и всё после неё на {...}
            local signature=$(echo "$fun_first_line" | sed 's/{.*$/\{...\}/')

            echo "@Composable" >> "$COMPONENTS_OUTPUT_FILE"
            echo "$signature" >> "$COMPONENTS_OUTPUT_FILE"
            echo "" >> "$COMPONENTS_OUTPUT_FILE"
            has_content=true
        else
            # Многострочная сигнатура
            local start_line=$fun_line_num
            local current_line=$start_line
            local signature="$fun_first_line"
            local bracket_balance=0

            # Считаем открывающие скобки в первой строке
            local open_count=$(echo "$fun_first_line" | grep -o "(" | wc -l)
            local close_count=$(echo "$fun_first_line" | grep -o ")" | wc -l)
            bracket_balance=$((open_count - close_count))

            # Собираем сигнатуру, пока не найдем закрывающую скобку и открывающую фигурную скобку
            while true; do
                current_line=$((current_line + 1))
                local line_content=$(sed -n "${current_line}p" "$file")

                # Если строка пустая или закончился файл, выходим из цикла
                if [ -z "$line_content" ] || [ $current_line -gt $((start_line + 100)) ]; then
                    break
                fi

                # Обновляем баланс скобок
                open_count=$(echo "$line_content" | grep -o "(" | wc -l)
                close_count=$(echo "$line_content" | grep -o ")" | wc -l)
                bracket_balance=$((bracket_balance + open_count - close_count))

                # Добавляем строку к сигнатуре
                signature="$signature
$line_content"

                # Если достигли закрывающей скобки и открывающей фигурной скобки и баланс скобок <= 0, выходим из цикла
                if [[ "$line_content" == *")"* && "$line_content" == *"{"* ]] && [ $bracket_balance -le 0 ]; then
                    break
                fi

                # Если достигли закрывающей скобки и равенства и баланс скобок <= 0, выходим из цикла
                if [[ "$line_content" == *")"* && "$line_content" == *"="* ]] && [ $bracket_balance -le 0 ]; then
                    break
                fi
            done

            # Заменяем фигурную скобку и всё после неё на {...}
            signature=$(echo "$signature" | sed 's/{.*$/\{...\}/')
            # В случае с равенством, добавляем {...}
            if [[ "$signature" == *"="* ]] && [[ "$signature" != *"{"* ]]; then
                signature="$signature {...}"
            fi

            echo "@Composable" >> "$COMPONENTS_OUTPUT_FILE"
            echo "$signature" >> "$COMPONENTS_OUTPUT_FILE"
            echo "" >> "$COMPONENTS_OUTPUT_FILE"
            has_content=true
        fi
    done

    # Обрабатываем классы с аннотацией @Stable
    grep -n "@Stable" "$file" | while read -r stable_line_info; do
        # Извлекаем номер строки
        local stable_line_num=$(echo "$stable_line_info" | cut -d':' -f1)

        # Ищем следующую строку с "class"
        local class_line_num=$(tail -n +$((stable_line_num+1)) "$file" | grep -n "class " | head -1 | cut -d':' -f1)

        if [ -z "$class_line_num" ]; then
            echo "No class declaration found after @Stable at line $stable_line_num"
            continue
        fi

        # Вычисляем абсолютный номер строки с "class"
        local class_line_num=$((stable_line_num + class_line_num))

        # Извлекаем строку с объявлением класса
        local class_line=$(sed -n "${class_line_num}p" "$file")

        # Пропускаем Preview классы
        if [[ "$class_line" == *"Preview"* ]]; then
            continue
        fi

        echo "@Stable" >> "$COMPONENTS_OUTPUT_FILE"
        echo "$class_line {..." >> "$COMPONENTS_OUTPUT_FILE"
        echo "" >> "$COMPONENTS_OUTPUT_FILE"
        has_content=true
    done

    # Обрабатываем sealed interface и обычные классы, которые могут быть связаны с дизайн-системой
    grep -n "sealed interface\|data object\|data class\|^class \|^object " "$file" | while read -r class_line_info; do
        # Извлекаем номер строки и содержимое
        local class_line_num=$(echo "$class_line_info" | cut -d':' -f1)
        local class_line=$(sed -n "${class_line_num}p" "$file")

        # Пропускаем приватные классы, вложенные классы с отступами и Preview классы
        if [[ "$class_line" == *"private "* ]] || [[ "$class_line" =~ ^[[:space:]] ]] || [[ "$class_line" == *"Preview"* ]]; then
            continue
        fi

        # Добавляем sealed interface, object, data class или class в XML
        echo "$class_line {..." >> "$COMPONENTS_OUTPUT_FILE"
        echo "" >> "$COMPONENTS_OUTPUT_FILE"
        has_content=true
    done

    # Закрываем компонент для файла только если в нем есть содержимое
    if [ "$has_content" = true ]; then
        echo "  </component>" >> "$COMPONENTS_OUTPUT_FILE"
    else
        # Если не было добавлено содержимое, удаляем открывающий тег компонента
        sed -i '' -e '$d' "$COMPONENTS_OUTPUT_FILE"
        sed -i '' -e '$d' "$COMPONENTS_OUTPUT_FILE"
        sed -i '' -e '$d' "$COMPONENTS_OUTPUT_FILE"
    fi
}

# Проверяем существование директории с компонентами
if [ ! -d "$COMPONENTS_PATH" ]; then
    echo "Error: Components directory not found: $COMPONENTS_PATH"
    exit 1
fi

# Находим и обрабатываем все Kotlin файлы в директории с компонентами
find "$COMPONENTS_PATH" -name "*.kt" | while read -r file; do
    extract_components "$file"
done

# Завершаем XML файл
echo "</components>" >> "$COMPONENTS_OUTPUT_FILE"

echo "Components extracted to $COMPONENTS_OUTPUT_FILE"

# Теперь исправляем возможные ошибки в XML файле (из второго скрипта)
echo "Fixing XML component tags..."

# Сохраняем заголовок XML
TEMP_FILE="$OUTPUT_DIR/design_system_components_fixed.xml"
echo "<components>" > "$TEMP_FILE"

# Обрабатываем каждый компонент
current_package=""
buffer=""
open_component=false

# Читаем файл построчно
while IFS= read -r line; do
    # Пропускаем первую строку с тегом <components>
    if [[ "$line" == "<components>" ]]; then
        continue
    fi

    # Пропускаем последнюю строку с закрывающим тегом
    if [[ "$line" == "</components>" ]]; then
        continue
    fi

    # Если встретили открывающий тег компонента
    if [[ "$line" == *"<component>"* ]]; then
        # Если уже был открыт компонент, закрываем его
        if [ "$open_component" = true ]; then
            echo "$buffer" >> "$TEMP_FILE"
            echo "  </component>" >> "$TEMP_FILE"
        fi

        # Начинаем новый компонент
        buffer="  <component>"
        open_component=true
        continue
    fi

    # Если встретили закрывающий тег компонента
    if [[ "$line" == *"</component>"* ]]; then
        buffer="$buffer"
        echo "$buffer" >> "$TEMP_FILE"
        echo "  </component>" >> "$TEMP_FILE"
        buffer=""
        open_component=false
        continue
    fi

    # Добавляем строку в текущий буфер
    if [ "$open_component" = true ]; then
        buffer="$buffer
$line"
    fi
done < "$COMPONENTS_OUTPUT_FILE"

# Если остался незакрытый компонент, закрываем его
if [ "$open_component" = true ]; then
    echo "$buffer" >> "$TEMP_FILE"
    echo "  </component>" >> "$TEMP_FILE"
fi

# Закрываем корневой элемент
echo "</components>" >> "$TEMP_FILE"

echo "XML tags fixed"

# Заменяем оригинальный файл исправленным
mv "$TEMP_FILE" "$COMPONENTS_OUTPUT_FILE"
echo "Final result saved to $COMPONENTS_OUTPUT_FILE"
