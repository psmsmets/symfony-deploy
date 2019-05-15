#!/bin/bash

##################################################
##
##  Default folder definitions
##
##################################################

# Usage info
show_help()
{
echo "
        Usage: deploy [-D domain] [-T Task] [-H]

        -D Domain    Specify the domain.
        -T Task      Specify the deploy task to run:
                         1) pull 
                         2) install
                         3) test
                         4) migrate 

                       1-4) all 

        For Example: ./deploy -T test

        -H              Help
"
exit 0
}

while getopts "HD:T:" flag; do
    case "${flag}" in
        D) domain=$OPTARG;;
        T) task=$OPTARG;;
        H) # HELP
            show_help
            ;;
        \?)
            echo "Invalid option: -$OPTARG. Use -H flag for help."
            exit
            ;;
    esac
done

# check deploy domain
case $domain in
    'yourdomain')
        git_username=""
        git_repository=""
        deploy_dir="/home/domains/yourdomain"
        master_dir="/tmp/${git_repository}_master_branch"
        public_dir="public_html"
        ;;
    *) 
        echo "Illegal deploy domain. Use -H flag for help."
        exit 1;
        ;;
esac

# check deploy task
case $task in
    'pull') execute=false;;
    'install') execute=false;;
    'test') execute=false;;
    'migrate') execute=true;;
    'all') execute=true;;
    *) 
        echo "Illegal deploy task. Use -H flag for help."
        exit 1;
        ;;
esac


# get current directory
cwd=$(pwd)

# check if path is absolute or relative
if [[ $deploy_dir == /* ]]; then deploy_path=$deploy_dir; else deploy_path=$cwd/$deploy_dir; fi
if [[ $master_dir == /* ]]; then master_path=$master_dir; else master_path=$cwd/$master_dir; fi

# feedback
echo "Settings"
echo "   respository : $git_username/$git_repository"
echo "    public dir : $public_dir"
echo "    deploy dir : $deploy_dir"
echo "    master dir : $master_dir"
echo "  current path : $cwd"
echo "   deploy path : $deploy_path"
echo "   master path : $master_path"
echo "          task : $task"
echo "       execute : $execute"

# Check if .env config file exists
if [ ! -f "$deploy_path/.env" ]; then
    echo "Error: Symfony 4 config file .env not found in deploy directory."
    exit 1;
fi

# pull
if [[ $task == 'pull' ]] || [[ $task == 'all' ]]; then 

    # remove git dir if exists
    if [ -d "$master_path" ]; then
        echo "Remove git master directory $master_path"
        rm -rf $master_path
    fi

    # clone git in dir
    echo "Pull git master repository to $master_path"
    git clone https://github.com/$git_username/$git_repository.git $master_path

fi

if [ ! -d "$master_path/.git" ]; then
    echo "Error: your first need to run with -T pull."
    exit 1;
fi

# install
if [[ $task == 'install' ]] || [[ $task == 'all' ]]; then 

    cd $master_path

    # Copy .env config file to master directory 
    cp $deploy_path/.env .

    # Generate composer dependencies for this (prod) environment
    composer require symfony/dotenv

    # Install/update vendors
    export APP_ENV=prod
    composer install --no-dev --optimize-autoloader

    # Install bundles
    php bin/console assets:install

    # Clear and warmup symfony cache
    APP_ENV=prod APP_DEBUG=0 php bin/console cache:clear
    APP_ENV=prod APP_DEBUG=0 php bin/console cache:warmup

    ##
    # Overwrite @ public_html/bundles
    ##
    # Fix fosckeditor config for fontawesome
    cp $public_dir/assets/js/ckeditor_config.js $public_dir/bundles/fosckeditor/config.js

fi

# install
if [[ $task == 'test' ]] || [[ $task == 'migrate' ]] || [[ $task == 'all' ]]; then

    # construct git folder list
    cd $master_path

    if [ ! -d "var" ] || [ ! -d "vendor" ]; then
        echo "Error: your first need to run with -T install."
        exit 1;
    fi
    general_files_and_folders=($(ls -d *))
    public_files_and_folders=( 'assets' 'bundles' 'check.php' 'index.php' )

    ####################
    #
    #   @ deploy_dir
    #
    ####################

    cd $deploy_path

    # clean deplod dir
    echo "Clean deploy directory \"$deploy_dir\""

    for element in "${general_files_and_folders[@]}"; do
        if [ "${element%/}" != "$public_dir" ]; then
            if [ -d "$element" ]; then
                echo "  - remove folder $element"
                if [ $execute = true ] ; then
                    rm -rf "$element"
                fi
            elif [ -f "$element" ]; then
                echo "  - remove file $element"
                if [ $execute = true ] ; then
                    rm -f "$element"
                fi
            fi
        fi
    done

    for element in "${public_files_and_folders[@]}"; do
        src="$public_dir/$element"
        if [ -d "$src" ]; then
            echo "  - remove folder $src"
            if [ $execute = true ] ; then
                rm -rf $src
            fi
        elif [ -f "$src" ]; then
            echo "  - remove file $src"
            if [ $execute = true ] ; then
                rm -f $src
            fi
        fi
    done

    ####################
    #
    #   @ master_dir
    #
    ####################

    cd $master_path

    # Copy all to deploy directory
    echo "Copy files from \"$master_dir\" to \"$deploy_dir\""
    
    for element in "${general_files_and_folders[@]}"; do
        if [ "${element%/}" != "$public_dir" ]; then
            if [ -d "$element" ]; then
                echo "  - copy folder $element"
                if [ $execute = true ] ; then
                    cp -r $element $deploy_path/
                fi
            elif [ -f "$element" ]; then
                echo "  - copy file $element"
                if [ $execute = true ] ; then
                    cp $element $deploy_path/
                fi
            fi
        fi
    done
    
    for element in "${public_files_and_folders[@]}"; do
        src="$public_dir/$element"
        if [ -d "$src" ]; then
            echo "  - copy folder $src"
            if [ $execute = true ] ; then
                cp -r $src $deploy_path/$public_dir/
            fi
        elif [ -f "$src" ]; then
            echo "  - copy file $src"
            if [ $execute = true ] ; then
                cp $src $deploy_path/$public_dir/
            fi
        fi
    done

    ####################
    #
    #   @ home
    #
    ####################

    cd $cwd

    echo "Clean."
    if [ -d "$master_path" ]; then
        echo "  - remove git master directory"
        if [ $execute = true ] ; then
            rm -rf $master_path
        fi
    fi

fi

echo "Deploy $task done."
case $task in
    'pull') echo "Now run with -T install";;
    'install') echo "Now run with -T test";;
    'test') echo "Now run with -T migrate";;
    'migrate','all') echo "Deploy completed.";;
esac
exit 0
