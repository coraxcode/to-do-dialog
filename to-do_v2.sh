#!/bin/bash

# Professional To-Do List Manager with Reminders
# Version: 3.0

# Configuration
TODO_FILE="todo.txt"
REMINDER_FILE="reminders.txt"
TEMP_FILE="/tmp/todo_temp.$$"
DIALOG_HEIGHT=20
DIALOG_WIDTH=70
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Initialize files and cleanup
init_files() {
    [ ! -f "$TODO_FILE" ] && touch "$TODO_FILE"
    [ ! -f "$REMINDER_FILE" ] && touch "$REMINDER_FILE"
}

cleanup() {
    rm -f "$TEMP_FILE"*
}
trap cleanup EXIT

# Check system dependencies
check_dependencies() {
    local missing_deps=()
    for dep in dialog date sleep notify-send awk sed grep; do
        command -v "$dep" >/dev/null 2>&1 || missing_deps+=("$dep")
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}Missing dependencies: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}Install: sudo apt-get install dialog libnotify-bin${NC}"
        exit 1
    fi
}

# Check notification system
check_notification_system() {
    [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && {
        echo -e "${YELLOW}Warning: No display environment detected${NC}"
        return 1
    }
    return 0
}

# Count functions
count_tasks() {
    [ -f "$TODO_FILE" ] && grep -c "^[^#REMINDER]" "$TODO_FILE" 2>/dev/null || echo "0"
}

count_reminders() {
    if [ -f "$REMINDER_FILE" ]; then
        local current_time=$(date +%s) count=0
        while IFS='|' read -r timestamp _ _ || [ -n "$timestamp" ]; do
            [ "$timestamp" -gt "$current_time" ] 2>/dev/null && count=$((count + 1))
        done < "$REMINDER_FILE"
        echo "$count"
    else
        echo "0"
    fi
}

# Display main menu
show_main_menu() {
    local task_count=$(count_tasks)
    local reminder_count=$(count_reminders)
    
    dialog --clear --title "Professional To-Do List Manager v3.0" \
        --menu "Tasks: $task_count | Active Reminders: $reminder_count\n\nChoose an option:" $DIALOG_HEIGHT $DIALOG_WIDTH 12 \
        1 "View All Tasks" \
        2 "Add New Task" \
        3 "Edit Tasks" \
        4 "Delete Tasks" \
        5 "Mark Tasks as Done" \
        6 "Delete All Tasks" \
        7 "Reminder Menu" \
        8 "System Information" \
        9 "Help" \
        0 "Exit" 2>"$TEMP_FILE"
}

# Display reminder menu
show_reminder_menu() {
    local reminder_count=$(count_reminders)
    
    dialog --clear --title "Reminder Management" \
        --menu "Active Reminders: $reminder_count\n\nChoose an option:" $DIALOG_HEIGHT $DIALOG_WIDTH 8 \
        1 "View All Reminders" \
        2 "Add New Reminder" \
        3 "Edit Reminder" \
        4 "Delete Reminder" \
        5 "Delete All Reminders" \
        6 "Cleanup Expired Reminders" \
        0 "Back to Main Menu" 2>"$TEMP_FILE"
}

# View tasks
view_tasks() {
    local task_count=$(count_tasks)
    
    if [ "$task_count" -eq 0 ]; then
        dialog --title "View Tasks" --msgbox "No tasks found.\n\nYour to-do list is empty." 10 50
        return
    fi
    
    grep "^[^#REMINDER]" "$TODO_FILE" | awk '{print NR ". " $0}' > "$TEMP_FILE"
    dialog --title "Your To-Do List ($task_count tasks)" --textbox "$TEMP_FILE" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Add task
add_task() {
    dialog --title "Add New Task" --inputbox "Enter your new task:" 10 60 2>"$TEMP_FILE"
    
    if [ $? -eq 0 ]; then
        local new_task=$(cat "$TEMP_FILE")
        if [ -n "$new_task" ]; then
            echo "$new_task" >> "$TODO_FILE"
            dialog --title "Success" --msgbox "Task added successfully!" 8 40
        else
            dialog --title "Error" --msgbox "Task cannot be empty!" 8 40
        fi
    fi
}

# Create task checklist
create_task_checklist() {
    local action="$1"
    local task_count=$(count_tasks)
    
    [ "$task_count" -eq 0 ] && {
        dialog --title "Error" --msgbox "No tasks available!" 8 40
        return 1
    }
    
    local checklist_items="" line_num=1
    
    while IFS= read -r line; do
        [[ "$line" =~ ^#REMINDER ]] && continue
        
        local display_line="$line"
        [ ${#display_line} -gt 50 ] && display_line="${display_line:0:47}..."
        checklist_items="$checklist_items $line_num \"$display_line\" off"
        line_num=$((line_num + 1))
    done < <(grep "^[^#REMINDER]" "$TODO_FILE")
    
    eval "dialog --title \"Select Tasks to $action\" --checklist \"Use SPACE to select, ENTER to confirm:\" $DIALOG_HEIGHT $DIALOG_WIDTH $task_count $checklist_items" 2>"$TEMP_FILE"
}

# Edit tasks
edit_tasks() {
    create_task_checklist "Edit" || return
    
    local selected_tasks=$(cat "$TEMP_FILE" | tr -d '"')
    [ -z "$selected_tasks" ] && {
        dialog --title "Information" --msgbox "No tasks selected for editing." 8 40
        return
    }
    
    grep "^[^#REMINDER]" "$TODO_FILE" > "$TEMP_FILE.tasks"
    
    for task_num in $selected_tasks; do
        local current_task=$(sed -n "${task_num}p" "$TEMP_FILE.tasks")
        
        dialog --title "Edit Task #$task_num" --inputbox "Edit your task:" 10 60 "$current_task" 2>"$TEMP_FILE.edit"
        
        if [ $? -eq 0 ]; then
            local edited_task=$(cat "$TEMP_FILE.edit")
            if [ -n "$edited_task" ]; then
                local line_count=0 target_line=0
                while IFS= read -r line; do
                    line_count=$((line_count + 1))
                    if [[ ! "$line" =~ ^#REMINDER ]]; then
                        target_line=$((target_line + 1))
                        if [ "$target_line" -eq "$task_num" ]; then
                            local escaped_task=$(echo "$edited_task" | sed 's/[[\.*^$()+?{|]/\\&/g')
                            sed -i "${line_count}s/.*/$escaped_task/" "$TODO_FILE"
                            break
                        fi
                    fi
                done < "$TODO_FILE"
            fi
        fi
    done
    
    dialog --title "Success" --msgbox "Selected tasks have been updated!" 8 40
}

# Delete tasks
delete_tasks() {
    create_task_checklist "Delete" || return
    
    local selected_tasks=$(cat "$TEMP_FILE" | tr -d '"')
    [ -z "$selected_tasks" ] && {
        dialog --title "Information" --msgbox "No tasks selected for deletion." 8 40
        return
    }
    
    dialog --title "Confirm Delete" --yesno "Are you sure you want to delete the selected tasks?" 10 50
    
    if [ $? -eq 0 ]; then
        local sorted_tasks=$(echo "$selected_tasks" | tr ' ' '\n' | sort -nr | tr '\n' ' ')
        local line_count=0 target_line=0
        > "$TEMP_FILE.result"
        
        while IFS= read -r line; do
            line_count=$((line_count + 1))
            if [[ "$line" =~ ^#REMINDER ]]; then
                echo "$line" >> "$TEMP_FILE.result"
            else
                target_line=$((target_line + 1))
                local should_delete=false
                for task_num in $sorted_tasks; do
                    [ "$target_line" -eq "$task_num" ] && { should_delete=true; break; }
                done
                [ "$should_delete" = false ] && echo "$line" >> "$TEMP_FILE.result"
            fi
        done < "$TODO_FILE"
        
        mv "$TEMP_FILE.result" "$TODO_FILE"
        dialog --title "Success" --msgbox "Selected tasks deleted successfully!" 8 40
    fi
}

# Mark tasks as done
mark_tasks_done() {
    create_task_checklist "Mark as Done" || return
    
    local selected_tasks=$(cat "$TEMP_FILE" | tr -d '"')
    [ -z "$selected_tasks" ] && {
        dialog --title "Information" --msgbox "No tasks selected to mark as done." 8 40
        return
    }
    
    grep "^[^#REMINDER]" "$TODO_FILE" > "$TEMP_FILE.tasks"
    
    for task_num in $selected_tasks; do
        local current_task=$(sed -n "${task_num}p" "$TEMP_FILE.tasks")
        echo "$current_task" | grep -q "^\[DONE\]" && continue
        
        local line_count=0 target_line=0
        while IFS= read -r line; do
            line_count=$((line_count + 1))
            if [[ ! "$line" =~ ^#REMINDER ]]; then
                target_line=$((target_line + 1))
                if [ "$target_line" -eq "$task_num" ]; then
                    local done_task="[DONE] $line"
                    local escaped_task=$(echo "$done_task" | sed 's/[[\.*^$()+?{|]/\\&/g')
                    sed -i "${line_count}s/.*/$escaped_task/" "$TODO_FILE"
                    break
                fi
            fi
        done < "$TODO_FILE"
    done
    
    dialog --title "Success" --msgbox "Selected tasks marked as done!" 8 40
}

# Delete all tasks
delete_all_tasks() {
    local task_count=$(count_tasks)
    
    [ "$task_count" -eq 0 ] && {
        dialog --title "Information" --msgbox "No tasks to delete!" 8 40
        return
    }
    
    dialog --title "Confirm Delete All" --yesno "Delete ALL $task_count tasks?\n\nThis cannot be undone!" 10 50
    
    if [ $? -eq 0 ]; then
        dialog --title "Final Confirmation" --yesno "FINAL WARNING!\n\nPermanently delete all tasks?" 10 40
        
        if [ $? -eq 0 ]; then
            grep "^#REMINDER" "$TODO_FILE" > "$TEMP_FILE.reminders" 2>/dev/null || touch "$TEMP_FILE.reminders"
            mv "$TEMP_FILE.reminders" "$TODO_FILE"
            dialog --title "Success" --msgbox "All tasks deleted successfully!" 8 40
        fi
    fi
}

# Add reminder
add_reminder() {
    dialog --title "Add New Reminder" --inputbox "Enter reminder text:" 10 60 2>"$TEMP_FILE"
    [ $? -ne 0 ] && return
    
    local reminder_text=$(cat "$TEMP_FILE")
    [ -z "$reminder_text" ] && {
        dialog --title "Error" --msgbox "Reminder text cannot be empty!" 8 40
        return
    }
    
    dialog --title "Set Reminder Time" --inputbox "Enter minutes from now:" 10 40 2>"$TEMP_FILE"
    [ $? -ne 0 ] && return
    
    local minutes=$(cat "$TEMP_FILE")
    [[ "$minutes" =~ ^[0-9]+$ ]] && [ "$minutes" -gt 0 ] || {
        dialog --title "Error" --msgbox "Please enter a valid number of minutes!" 8 40
        return
    }
    
    local current_time=$(date +%s)
    local reminder_time=$((current_time + minutes * 60))
    local reminder_date=$(date -d "@$reminder_time" "+%Y-%m-%d %H:%M:%S")
    
    echo "$reminder_time|$reminder_text|$reminder_date" >> "$REMINDER_FILE"
    start_reminder "$reminder_time" "$reminder_text" &
    
    dialog --title "Success" --msgbox "Reminder set for $reminder_date\n\nReminder: $reminder_text" 12 60
}

# Start reminder process
start_reminder() {
    local reminder_time="$1" reminder_text="$2"
    local current_time=$(date +%s)
    local sleep_time=$((reminder_time - current_time))
    
    [ "$sleep_time" -le 0 ] && return
    
    (
        sleep "$sleep_time"
        if grep -q "^$reminder_time|" "$REMINDER_FILE" 2>/dev/null; then
            command -v notify-send >/dev/null 2>&1 && \
                notify-send "To-Do Reminder" "$reminder_text" -i dialog-information -t 10000
            sed -i "/^$reminder_time|/d" "$REMINDER_FILE"
        fi
    ) &
}

# View reminders
view_reminders() {
    local reminder_count=$(count_reminders)
    
    [ "$reminder_count" -eq 0 ] && {
        dialog --title "View Reminders" --msgbox "No active reminders found." 10 50
        return
    }
    
    local line_num=1 current_time=$(date +%s)
    > "$TEMP_FILE"
    
    while IFS='|' read -r timestamp text date_str || [ -n "$timestamp" ]; do
        if [ "$timestamp" -gt "$current_time" ] 2>/dev/null; then
            echo "$line_num. [$date_str] $text" >> "$TEMP_FILE"
            line_num=$((line_num + 1))
        fi
    done < "$REMINDER_FILE"
    
    dialog --title "Active Reminders ($reminder_count)" --textbox "$TEMP_FILE" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Create reminder checklist
create_reminder_checklist() {
    local action="$1"
    local reminder_count=$(count_reminders)
    
    [ "$reminder_count" -eq 0 ] && {
        dialog --title "Error" --msgbox "No active reminders available!" 8 40
        return 1
    }
    
    local checklist_items="" line_num=1 current_time=$(date +%s)
    
    while IFS='|' read -r timestamp text date_str || [ -n "$timestamp" ]; do
        if [ "$timestamp" -gt "$current_time" ] 2>/dev/null; then
            local display_text="$text"
            [ ${#display_text} -gt 30 ] && display_text="${display_text:0:27}..."
            checklist_items="$checklist_items $line_num \"[$date_str] $display_text\" off"
            line_num=$((line_num + 1))
        fi
    done < "$REMINDER_FILE"
    
    eval "dialog --title \"Select Reminders to $action\" --checklist \"Use SPACE to select, ENTER to confirm:\" $DIALOG_HEIGHT $DIALOG_WIDTH $reminder_count $checklist_items" 2>"$TEMP_FILE"
}

# Edit reminder
edit_reminder() {
    create_reminder_checklist "Edit" || return
    
    local selected_reminders=$(cat "$TEMP_FILE" | tr -d '"')
    [ -z "$selected_reminders" ] && return
    
    for reminder_num in $selected_reminders; do
        local line_num=1 current_time=$(date +%s)
        
        while IFS='|' read -r timestamp text date_str || [ -n "$timestamp" ]; do
            if [ "$timestamp" -gt "$current_time" ] 2>/dev/null; then
                if [ "$line_num" -eq "$reminder_num" ]; then
                    dialog --title "Edit Reminder #$reminder_num" --inputbox "Edit reminder text:" 10 60 "$text" 2>"$TEMP_FILE.edit"
                    
                    if [ $? -eq 0 ]; then
                        local new_text=$(cat "$TEMP_FILE.edit")
                        if [ -n "$new_text" ]; then
                            local escaped_old=$(echo "$timestamp|$text|$date_str" | sed 's/[[\.*^$()+?{|]/\\&/g')
                            local escaped_new=$(echo "$timestamp|$new_text|$date_str" | sed 's/[[\.*^$()+?{|]/\\&/g')
                            sed -i "s/$escaped_old/$escaped_new/" "$REMINDER_FILE"
                        fi
                    fi
                    break
                fi
                line_num=$((line_num + 1))
            fi
        done < "$REMINDER_FILE"
    done
    
    dialog --title "Success" --msgbox "Selected reminders updated!" 8 40
}

# Delete reminder
delete_reminder() {
    create_reminder_checklist "Delete" || return
    
    local selected_reminders=$(cat "$TEMP_FILE" | tr -d '"')
    [ -z "$selected_reminders" ] && return
    
    dialog --title "Confirm Delete" --yesno "Delete the selected reminders?" 10 50
    
    if [ $? -eq 0 ]; then
        local sorted_reminders=$(echo "$selected_reminders" | tr ' ' '\n' | sort -nr | tr '\n' ' ')
        
        for reminder_num in $sorted_reminders; do
            local line_num=1 current_time=$(date +%s)
            
            while IFS='|' read -r timestamp text date_str || [ -n "$timestamp" ]; do
                if [ "$timestamp" -gt "$current_time" ] 2>/dev/null; then
                    if [ "$line_num" -eq "$reminder_num" ]; then
                        local escaped_line=$(echo "$timestamp|$text|$date_str" | sed 's/[[\.*^$()+?{|]/\\&/g')
                        sed -i "/$escaped_line/d" "$REMINDER_FILE"
                        break
                    fi
                    line_num=$((line_num + 1))
                fi
            done < "$REMINDER_FILE"
        done
        
        dialog --title "Success" --msgbox "Selected reminders deleted!" 8 40
    fi
}

# Delete all reminders
delete_all_reminders() {
    local reminder_count=$(count_reminders)
    
    [ "$reminder_count" -eq 0 ] && {
        dialog --title "Information" --msgbox "No reminders to delete!" 8 40
        return
    }
    
    dialog --title "Confirm Delete All" --yesno "Delete ALL $reminder_count reminders?\n\nThis cannot be undone!" 10 50
    
    [ $? -eq 0 ] && {
        > "$REMINDER_FILE"
        dialog --title "Success" --msgbox "All reminders deleted!" 8 40
    }
}

# Cleanup expired reminders
cleanup_expired_reminders() {
    local current_time=$(date +%s) temp_file="$TEMP_FILE.cleanup" count=0
    
    > "$temp_file"
    while IFS='|' read -r timestamp text date_str || [ -n "$timestamp" ]; do
        if [ "$timestamp" -gt "$current_time" ] 2>/dev/null; then
            echo "$timestamp|$text|$date_str" >> "$temp_file"
        else
            count=$((count + 1))
        fi
    done < "$REMINDER_FILE"
    
    mv "$temp_file" "$REMINDER_FILE"
    dialog --title "Cleanup Complete" --msgbox "Cleaned up $count expired reminders." 8 40
}

# Restore reminders on startup
restore_reminders() {
    local current_time=$(date +%s)
    
    while IFS='|' read -r timestamp text date_str || [ -n "$timestamp" ]; do
        [ "$timestamp" -gt "$current_time" ] 2>/dev/null && start_reminder "$timestamp" "$text" &
    done < "$REMINDER_FILE"
}

# Show system information
show_system_info() {
    local info_text="System Information\n\n"
    info_text+="Version: 3.0 Optimized\n"
    info_text+="Location: $SCRIPT_DIR\n"
    info_text+="Tasks: $(count_tasks)\n"
    info_text+="Reminders: $(count_reminders)\n"
    info_text+="System: $(uname -s) $(uname -r)\n"
    info_text+="Shell: $SHELL\n"
    
    command -v notify-send >/dev/null 2>&1 && \
        info_text+="Notifications: Available\n" || \
        info_text+="Notifications: Not Available\n"
    
    dialog --title "System Information" --msgbox "$info_text" 16 50
}

# Show help
show_help() {
    local help_text="Professional To-Do List Manager v3.0\n\n"
    help_text+="FEATURES:\n"
    help_text+="• Task Management (Add, Edit, Delete, Mark Done)\n"
    help_text+="• Reminder System with Notifications\n"
    help_text+="• Background Processing\n"
    help_text+="• Automatic Cleanup\n\n"
    help_text+="SHORTCUTS:\n"
    help_text+="• TAB/Arrows: Navigate\n"
    help_text+="• SPACE: Select\n"
    help_text+="• ENTER: Confirm\n"
    help_text+="• ESC: Cancel\n\n"
    help_text+="All data stored in plain text files.\n"
    
    dialog --title "Help" --msgbox "$help_text" 18 60
}

# Handle reminder menu
handle_reminder_menu() {
    while true; do
        show_reminder_menu
        [ $? -ne 0 ] && break
        
        local choice=$(cat "$TEMP_FILE")
        
        case $choice in
            1) view_reminders ;;
            2) add_reminder ;;
            3) edit_reminder ;;
            4) delete_reminder ;;
            5) delete_all_reminders ;;
            6) cleanup_expired_reminders ;;
            0) break ;;
            *) dialog --title "Error" --msgbox "Invalid option!" 8 40 ;;
        esac
    done
}

# Main program
main() {
    check_dependencies
    check_notification_system
    init_files
    restore_reminders
    cleanup_expired_reminders
    
    while true; do
        show_main_menu
        [ $? -ne 0 ] && break
        
        local choice=$(cat "$TEMP_FILE")
        
        case $choice in
            1) view_tasks ;;
            2) add_task ;;
            3) edit_tasks ;;
            4) delete_tasks ;;
            5) mark_tasks_done ;;
            6) delete_all_tasks ;;
            7) handle_reminder_menu ;;
            8) show_system_info ;;
            9) show_help ;;
            0) 
                dialog --title "Goodbye" --msgbox "Thank you for using To-Do List Manager!\n\nReminders continue in background." 10 50
                break
                ;;
            *) dialog --title "Error" --msgbox "Invalid option!" 8 40 ;;
        esac
    done
    
    clear
    echo -e "${GREEN}To-Do List Manager v3.0 - Session ended${NC}"
    echo -e "${YELLOW}Active reminders continue running in background${NC}"
}

# Run the program
main "$@"
