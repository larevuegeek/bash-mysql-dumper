#!/bin/bash
# v1.0
# Ce script effectue une sauvegarde complète de toutes les bases de données MySQL
# Il conserve les sauvegardes pendant X jours (BACKUP_EXPIRATION_DAYS)
# Ensuite il purge automatiquement les sauvegardes expirées

# Vous pouvez activer la compression GZIP
# Vous pouvez ajouter les options --drop-table et drop-database au besoin
# Vous pouvez activer le mode VERBOSE pour avoir des infos pendant la sauvegarde

#### AMELIORATIONS A VENIR 
# Ajout d'un mode de sauvegarde par tables/databases au choix
# Ajout d'un envoi de mail récapitulatif
# Vérifier le repertoire à purger lors de la rotation des sauvgerdes

#Chemin de destination des fichiers de sauvegarde
BACKUP_DIR="/var/backups/mysql/"

#Nom d'hôte ou adresse IP du serveur de base de données
BACKUP_HOST="localhost"

#Nom d'utilisateur de la base de données
BACKUP_USER="root"

#Mot de passe de l'utilisateur de la base de données
BACKUP_PASSWORD="xxx"


#### Paramètres

#Délai de conservation des sauvegardes en jours
BACKUP_EXPIRATION_DAYS=10

#Mode verbose : affiche des informations lors du dump
VERBOSE="Y"

#Active la compression GZIP ou non
GZIP_COMPRESSION="N"

#Ajoute l'option --add-drop-database lors du dump
ADD_DROP_DATABASE="N"

#Ajoute l'option --add-drop-table lors du dump
ADD_DROP_TABLE="Y"

####

#heure du début du script
START_TIME=$(date +%s%N)

#On vérifie que l'utilisateur est en root ou en sudo
if [[ "$EUID" != 0 ]]; then
    echo "Vous devez executer ce script en root ou avec sudo"
    exit 13
fi 

### Check Mysql
PING=$((mysqladmin ping -h $BACKUP_HOST --user="$BACKUP_USER" --password="$BACKUP_PASSWORD") 2>&1)
if [ "$PING" != "mysqld is alive" ]; then
    echo "Error: Unable to connected to MySQL Server, exiting !!"
    echo $PING
    ##if mail sendmail
    exit 101
fi


#Vérifie si le dossier de destination existe sinon le créé
[ ! -d "$BACKUP_DIR" ] && mkdir -p $BACKUP_DIR

###On crée le dossier du portant comme nom la date du jour + Hostname
### YYY-MMMM-DD-NOM-DU-SERVER
DESTINATION_DIR=$(date +"%Y-%m-%d")
DESTINATION_DIR="${BACKUP_DIR}${DESTINATION_DIR}-${BACKUP_HOST}"
[ ! -d "$DESTINATION_DIR" ] && mkdir -p $DESTINATION_DIR

#Récupération de la liste des bases de données
databases=$(mysql --host="$BACKUP_HOST" --user="$BACKUP_USER" --password="$BACKUP_PASSWORD" --execute="SHOW DATABASES;" --batch)

#Vérification si on a bien des bases de données
if [ -z "$databases" ]; then
    echo "Error: no databases found !!"
    ##if mail sendmail
    exit 61
fi

i=1
n=1
#on parcours la liste des bases de données
for database in $databases;
do  
    if [ $i -gt $n ] 
    then
        
        #heure du début de dump de la database en cours
        START_DB_TIME=$(date +%s%N)

        if [ "$VERBOSE" == "Y" ]; then 
            echo "traitement de la base "$database" en cours..."
        fi

        DATABASE_DIR="${DESTINATION_DIR}/${database}"

        ##on créé le dossier de destination
        [ ! -d "$DATABASE_DIR" ] && mkdir -p $DATABASE_DIR

        #on se place dans le dossier de destination
        cd $DATABASE_DIR

        #debut de la commande MySQL DUMP
        MYSQLDUMP_CDM="--host="$BACKUP_HOST" --user="$BACKUP_USER" --password="$BACKUP_PASSWORD" --single-transaction"
        
        #Ajout du DROP TABLE
        if [[ $ADD_DROP_DATABASE == "Y" || $ADD_DROP_DATABASE == "y" ]]; then
            MYSQLDUMP_CDM="${MYSQLDUMP_CDM} --add-drop-table"
        fi

        #Ajout du DROP DATABASE
        if [[ $ADD_DROP_TABLE == "Y" || $ADD_DROP_TABLE == "y" ]]; then
            MYSQLDUMP_CDM="${MYSQLDUMP_CDM} --add-drop-database"
        fi

        #Execution du dump avec gestion de la compression GZ
        if [[ $GZIP_COMPRESSION == "Y" || $GZIP_COMPRESSION == "y" ]]; then
            FILENAME="$database.sql.gz"
            mysqldump $MYSQLDUMP_CDM --databases $database > $FILENAME | gzip -c > $FILENAME
        else #Execution du dump sans compression
            FILENAME="$database.sql"
            mysqldump $MYSQLDUMP_CDM --databases $database > $FILENAME
        fi

        #On calcule la taille du fichier sauvegardé
        database_filesize=$(du -h "$FILENAME" | awk '{ print $1}')

        if [ "$VERBOSE" == "Y" ]; then 
            echo $database_filesize" sauvegardés"
        fi
    
        #heure de fin de dump de la database en cours
        END_DB_TIME=$(date +%s%N)

        if [ "$VERBOSE" == "Y" ]; then 
            TIME_DB_ELAPSED="$((($END_DB_TIME-$START_DB_TIME)/1000000))"
            TIME_DB_ELAPSED_SEC=`echo "scale=2;${TIME_DB_ELAPSED}/1000" | bc`
            echo "Durée de la sauvegarde "$database" : "$TIME_DB_ELAPSED_SEC" seconde(s)"
        fi
    fi
    let "i+=1" 
done

#heure de fin de script
END_TIME="$(date +%s%N)"

#Durée d'execution du script
TIME_ELAPSED="$((($END_TIME-$START_TIME)/1000000))"
TIME_ELAPSED_SEC=`echo "scale=2;${TIME_ELAPSED}/1000" | bc`

#Taille totale des fichiers sauvegardées
if [ "$VERBOSE" == "Y" ]; then 
    total_filesize=$(du -sh "$DESTINATION_DIR" | awk '{ print $1}')
    echo "Taille totale des bases de données : "$total_filesize""
    echo "Durée totale de la sauvegarde : "$TIME_ELAPSED_SEC" secondes"
fi

#### Nettoyage des sauvgardes
if [ ! -z "$BACKUP_EXPIRATION_DAYS" ]; then
    if [ "$VERBOSE" == "Y" ]; then 
        echo -en "$(date) : nettoyage des dossiers : "
    fi
    find $BACKUP_DIR/ -maxdepth 1 -mtime $BACKUP_EXPIRATION_DAYS -type d -exec rm -rf {} \;
fi