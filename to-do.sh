#!/bin/bash

# Professional To-Do List Manager
# Author: Shell Script Expert
# Version: 2.0

# Configuration
TODO_FILE="$HOME/Documents/todo.txt"
TEMP_FILE="/tmp/todo_temp.$$"
DIALOG_HEIGHT=20
DIALOG_WIDTH=70

# Initialize todo file if it doesn't exist
init_todo_file() {
    if [ ! -f "$TODO_FILE" ]; then
        touch "$TODO_FILE"
    fi
}

# Clean up temporary files on exit
cleanup() {
    rm -f "$TEMP_FILE"*
}
trap cleanup EXIT

# Check if dialog is available
check_dialog() {
    if ! command -v dialog >/dev/null 2>&1; then
        echo "Error: dialog command not found. Please install dialog package."
        echo "Ubuntu/Debian: sudo apt-get install dialog"
        echo "RedHat/CentOS: sudo yum install dialog"
        echo "Arch Linux: sudo pacman -S dialog"
        exit 1
    fi
}

# Display main menu
show_main_menu() {
    dialog --clear --title "Professional To-Do List Manager" \
        --menu "Choose an option:" $DIALOG_HEIGHT $DIALOG_WIDTH 11 \
        1 "View All Tasks" \
        2 "Add New Task" \
        3 "Edit Tasks" \
        4 "Delete Tasks" \
        5 "Toggle Status" \
	6 "Task Statistics" \
        7 "Delete All Tasks" \
        8 "Exit" 2>"$TEMP_FILE"
    
    return $?
}

# Count total tasks
count_tasks() {
    if [ -f "$TODO_FILE" ]; then
        grep -c "^" "$TODO_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Display all tasks
view_tasks() {
    local task_count=$(count_tasks)
    
    if [ "$task_count" -eq 0 ]; then
        dialog --title "View Tasks" --msgbox "No tasks found.\n\nYour to-do list is empty." 10 50
        return
    fi
    
    # Create numbered task list
    awk '{print NR ". " $0}' "$TODO_FILE" > "$TEMP_FILE"
    
    dialog --title "Your To-Do List ($task_count tasks)" \
        --textbox "$TEMP_FILE" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Add new task
add_task() {
    dialog --title "Add New Task" \
        --inputbox "Enter your new task:" 10 60 2>"$TEMP_FILE"
    
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

# Create checklist for task selection
create_task_checklist() {
    local action="$1"
    local task_count=$(count_tasks)
    
    if [ "$task_count" -eq 0 ]; then
        dialog --title "Error" --msgbox "No tasks available!" 8 40
        return 1
    fi
    
    # Create checklist items
    local checklist_items=""
    local line_num=1
    
    while IFS= read -r line; do
        # Truncate long lines for display
        local display_line="$line"
        if [ ${#display_line} -gt 50 ]; then
            display_line="${display_line:0:47}..."
        fi
        checklist_items="$checklist_items $line_num \"$display_line\" off"
        line_num=$((line_num + 1))
    done < "$TODO_FILE"
    
    eval "dialog --title \"Select Tasks to $action\" --checklist \"Use SPACE to select, ENTER to confirm:\" $DIALOG_HEIGHT $DIALOG_WIDTH $task_count $checklist_items" 2>"$TEMP_FILE"
    
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Edit selected tasks
edit_tasks() {
    if ! create_task_checklist "Edit"; then
        return
    fi
    
    local selected_tasks=$(cat "$TEMP_FILE")
    if [ -z "$selected_tasks" ]; then
        dialog --title "Information" --msgbox "No tasks selected for editing." 8 40
        return
    fi
    
    # Remove quotes and process each selected task
    selected_tasks=$(echo "$selected_tasks" | tr -d '"')
    
    for task_num in $selected_tasks; do
        # Get current task content
        local current_task=$(sed -n "${task_num}p" "$TODO_FILE")
        
        dialog --title "Edit Task #$task_num" \
            --inputbox "Edit your task:" 10 60 "$current_task" 2>"$TEMP_FILE.edit"
        
        if [ $? -eq 0 ]; then
            local edited_task=$(cat "$TEMP_FILE.edit")
            if [ -n "$edited_task" ]; then
                # Escape special characters for sed
                edited_task=$(echo "$edited_task" | sed 's/[[\.*^$()+?{|]/\\&/g')
                # Update the task
                sed -i "${task_num}s/.*/$edited_task/" "$TODO_FILE"
            else
                dialog --title "Error" --msgbox "Task #$task_num cannot be empty! Skipping..." 8 50
            fi
        fi
    done
    
    dialog --title "Success" --msgbox "Selected tasks have been updated!" 8 40
}

# Delete selected tasks
delete_tasks() {
    if ! create_task_checklist "Delete"; then
        return
    fi
    
    local selected_tasks=$(cat "$TEMP_FILE")
    if [ -z "$selected_tasks" ]; then
        dialog --title "Information" --msgbox "No tasks selected for deletion." 8 40
        return
    fi
    
    # Show confirmation with selected tasks
    local task_list=""
    selected_tasks=$(echo "$selected_tasks" | tr -d '"')
    
    for task_num in $selected_tasks; do
        local task_content=$(sed -n "${task_num}p" "$TODO_FILE")
        task_list="$task_list\n$task_num. $task_content"
    done
    
    dialog --title "Confirm Delete" \
        --yesno "Are you sure you want to delete these tasks?$task_list" 15 70
    
    if [ $? -eq 0 ]; then
        # Sort task numbers in reverse order to avoid line number shifting
        local sorted_tasks=$(echo "$selected_tasks" | tr ' ' '\n' | sort -nr | tr '\n' ' ')
        
        # Delete tasks from bottom to top
        for task_num in $sorted_tasks; do
            sed -i "${task_num}d" "$TODO_FILE"
        done
        
        dialog --title "Success" --msgbox "Selected tasks deleted successfully!" 8 40
    fi
}

# Mark tasks as done
toggle_task_status() {
    if ! create_task_checklist "Toggle Status"; then
        return
    fi
    
    local selected_tasks=$(cat "$TEMP_FILE")
    if [ -z "$selected_tasks" ]; then
        dialog --title "Information" --msgbox "No tasks selected to toggle status." 8 40
        return
    fi
    
    # Remove quotes and process each selected task
    selected_tasks=$(echo "$selected_tasks" | tr -d '"')
    
    local marked_done=0
    local marked_undone=0
    
    for task_num in $selected_tasks; do
        # Get current task content
        local current_task=$(sed -n "${task_num}p" "$TODO_FILE")
        
        # Check if task is already marked as done
        if echo "$current_task" | grep -q "^\[DONE\]"; then
            # Remove [DONE] prefix
            local undone_task=$(echo "$current_task" | sed 's/^\[DONE\] //')
            undone_task=$(echo "$undone_task" | sed 's/[[\.*^$()+?{|]/\\&/g')
            sed -i "${task_num}s/.*/$undone_task/" "$TODO_FILE"
            marked_undone=$((marked_undone + 1))
        else
            # Add [DONE] prefix
            local done_task="[DONE] $current_task"
            done_task=$(echo "$done_task" | sed 's/[[\.*^$()+?{|]/\\&/g')
            sed -i "${task_num}s/.*/$done_task/" "$TODO_FILE"
            marked_done=$((marked_done + 1))
        fi
    done
    
    # Show informative message about what was changed
    local message=""
    if [ $marked_done -gt 0 ] && [ $marked_undone -gt 0 ]; then
        message="Tasks updated!\n\nMarked as done: $marked_done\nMarked as undone: $marked_undone"
    elif [ $marked_done -gt 0 ]; then
        message="$marked_done task(s) marked as done!"
    elif [ $marked_undone -gt 0 ]; then
        message="$marked_undone task(s) marked as undone!"
    fi
    
    dialog --title "Success" --msgbox "$message" 10 40
}

# Count done and pending tasks
# Count done and pending tasks
show_task_stats() {
    local task_count=$(count_tasks)
    
    # Ensure task_count is numeric
    task_count=${task_count:-0}
    if ! [[ "$task_count" =~ ^[0-9]+$ ]]; then
        task_count=0
    fi

    if [ "$task_count" -eq 0 ]; then
        dialog --title "Task Statistics" --msgbox "No tasks found.\n\nYour to-do list is empty." 10 50
        return
    fi

    local done_count=$(grep -c "^\[DONE\]" "$TODO_FILE" 2>/dev/null || echo "0")
    # Ensure done_count is numeric
    done_count=${done_count:-0}
    if ! [[ "$done_count" =~ ^[0-9]+$ ]]; then
        done_count=0
    fi
    
    local pending_count=$((task_count - done_count))

    dialog --title "Task Statistics" \
        --msgbox "Task Summary:\n\nDone: $done_count\nPending: $pending_count\nTotal: $task_count" 12 40
}

# Delete all tasks
delete_all_tasks() {
    local task_count=$(count_tasks)
    
    if [ "$task_count" -eq 0 ]; then
        dialog --title "Information" --msgbox "No tasks to delete!" 8 40
        return
    fi
    
    dialog --title "Confirm Delete All" \
        --yesno "Are you sure you want to delete ALL $task_count tasks?\n\nThis action cannot be undone!" 10 60
    
    if [ $? -eq 0 ]; then
        # Double confirmation for safety
        dialog --title "Final Confirmation" \
            --yesno "FINAL WARNING!\n\nThis will permanently delete all your tasks.\n\nAre you absolutely sure?" 12 50
        
        if [ $? -eq 0 ]; then
            > "$TODO_FILE"  # Empty the file
            dialog --title "Success" --msgbox "All tasks deleted successfully!" 8 40
        fi
    fi
}

# Main program loop
main() {
    # Initialize
    check_dialog
    init_todo_file
    
    while true; do
        show_main_menu
        
        if [ $? -ne 0 ]; then
            break
        fi
        
        local choice=$(cat "$TEMP_FILE")
        
        case $choice in
            1)
                view_tasks
                ;;
            2)
                add_task
                ;;
            3)
                edit_tasks
                ;;
            4)
                delete_tasks
                ;;
            5)
                toggle_task_status
                ;;
            6)
		show_task_stats
		;;
            7)
                delete_all_tasks
                ;;
            8)
                dialog --title "Goodbye" --msgbox "Thank you for using To-Do List Manager!" 8 40
                break
                ;;
            *)
                dialog --title "Error" --msgbox "Invalid option selected!" 8 40
                ;;
        esac
    done
    
    clear
    echo "To-Do List Manager - Session ended"
}

# Run the program
main
