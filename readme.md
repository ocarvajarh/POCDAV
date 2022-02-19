# Instalación

## Activación Suscripciones Trial
https://access.redhat.com/activate
William Ramirez (wilramne@davivienda.loc)

## Obtener pull secrets cloud.redhat.com

## PC para instalación (MAC o Linux)
- Requiere: ssh key, programa de instalación, pull secret

## Versión VMWare
- Confirmar versión VMWare

## vSphere Credentials

## NFS 
Requerido para el registry. Servidor NFS existente o se debe instalara uno nuevo

## Configuración de firewall
Ver documento o link https://docs.openshift.com/container-platform/4.2/installing/install_config/configuring-firewall.html#configuring-firewall

## DHCP
Asegúrese de que el servidor DHCP esté configurado para proporcionar direcciones IP persistentes y nombres de host a las máquinas del clúster.
Por lo tanto, es importante tener DHCP con reserva de dirección en su lugar. Puede hacerlo con el filtrado de direcciones MAC para la reserva de IP. Al crear sus máquinas virtuales, deberá tomar nota de la dirección MAC asignada para configurar su servidor DHCP para la reserva de IP.

## DNS
Combinación del "cluster id" y el dominio base, por ejemplo con un nombre de ocplocal y dominio davivienda.loc requiere las entradas de tipo:

master1.ocplocal.davivienda.loc
master2.ocplocal.davivienda.loc
...
worker3.ocplocal.davivienda.loc
bootstrap.
etcd-0.
etcd-2.

api.ocplocal.davivienda.loc                 LB(masters)
api-int.ocplocal.davivienda.loc             LB(masters)
*.apps.ocplocal.davivienda.loc              LB(worker nodes), no solo infra

### SRV DNS Records
### _service._proto.name.                            TTL    class SRV priority weight port target.
_etcd-server-ssl._tcp.ocplocal.davivienda.com  86400 IN    SRV 0        10     2380 etcd-0.ocplocal.davivienda.com.
_etcd-server-ssl._tcp.ocplocal.davivienda.com  86400 IN    SRV 0        10     2380 etcd-1.ocplocal.davivienda.com.
_etcd-server-ssl._tcp.ocplocal.davivienda.com  86400 IN    SRV 0        10     2380 etcd-2.ocplocal.davivienda.com.


Todos los registros DNS deben ser subdominios del dominio base (davivienda.loc) e incluir el nombre del clúster

También se debe realizar la configuración de reverse DNS adecuada

Verificar todo con dig antes de continuar, ver https://blog.openshift.com/openshift-4-2-vsphere-install-quickstart/

## Servidor HTTP
Servidor HTTP para cargar el archivo bootstrap.ign de manera temporal 


## Certificados de instalación
Los archivos de configuración de Ignition que genera el programa de instalación contienen certificados que caducan después de 24 horas. Debe completar la instalación del clúster y mantener el clúster en funcionamiento durante 24 horas en un estado no degradado para garantizar que la primera rotación del certificado haya finalizado



## SSH key
## Instaladores
## Crear archivo de instalación (install-config.yaml)
- Después de configurado tomar backup antes de ejecutar la instalación
## Crear archivos de Ignition
- 
## Modificar parámetros de red
- archivo <installation_directory>/manifests/cluster-network-03-config.yml  (se debe tomar backup antes de lanzar la instalación)

## Crear máquinas RHCOS en vSphere

## Autoscale
- parámetro horizontal-pod-autoscaler-downscale-stabilization por defecto a 5 minutos


## Comandos para POC

   https://www.opentlc.com/labs/3scale_advanced_development/04_1_Homework_Assignment_Lab.html

    mvn -DskipTests fabric8:deploy -Popenshift

    oc set resources deployment/catalog-service --limits=cpu=400m,memory=512Mi --requests=cpu=200m,memory=256Mi
    oc autoscale deployment/catalog-service --min 1 --max 5 --cpu-percent=40

    https://github.com/fabric8-quickstarts/spring-boot-cxf-jaxrs.git

    spring-boot-cxf-jaxrs-1.0.0.fuse-740018-redhat-00002


    oc rollout resume deploy/inventory-service -n sandbox

### Redis
    oc patch rec <cluster-name> --type merge --patch '{"spec":{"clusterRecovery":true}}'

    oc describe rec | grep State"   -> verificar que quede en Running

    oc exec -it <pod-name> rladmin recover all

    password: 0B4mYlfp

## Gogs

devmaster:openshift
https://github.com/jboss-openshift/openshift-quickstarts

SKIP_TLS.... en el config map para evitar que valide los certificados en los webhooks

    

## Cluster local con Proxy
Con estas  variables, 

-Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true


Se pudieron evitar errores como los siguientes, claro que esto solo funcionaría para builds basados en mvn, no para PHP

    [WARNING] Could not transfer metadata org.apache.maven.plugins:maven-shade-plugin/maven-metadata.xml from/to central (https://repo1.maven.org/maven2): PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
    [WARNING] Could not transfer metadata org.apache.maven.plugins:maven-shade-plugin/maven-metadata.xml from/to redhat-ga-plugin-repository (https://maven.repository.redhat.com/ga/): PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
    [WARNING] Could not transfer metadata org.apache.maven.plugins:maven-shade-plugin/maven-metadata.xml from/to redhat-ea-plugin-repository (https://maven.repository.redhat.com/earlyaccess/all/): PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
    [WARNING] Could not transfer metadata org.apache.maven.plugins:maven-shade-plugin/maven-metadata.xml from/to jboss-eap-plugin-repository (https://maven.repository.redhat.com/techpreview/all): PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target


Sin esto el build fallaba sin importar que aparentemente los certificados de la CA interna estaban correctamente en la ruta /etc/ssl/certs, /etc/ssl apunta a /etc/pki/tls

-- En el pod build
sh-4.2# ls -ltr /etc/pki/tls/certs/
total 8
lrwxrwxrwx. 1 root root   55 Jan 27 09:52 ca-bundle.trust.crt -> /etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt
lrwxrwxrwx. 1 root root   49 Jan 27 09:52 ca-bundle.crt -> /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
-rw-r--r--. 1 root root 4634 Apr  1 02:38 cluster.crt


-- En el nodo
[root@worker4 ~]# ls -ltr /etc/ssl/certs
lrwxrwxrwx. 1 root root 16 Feb 20 17:01 /etc/ssl/certs -> ../pki/tls/certs
[root@worker4 ~]# ls -ltr /etc/ssl/certs/
total 0
lrwxrwxrwx. 1 root root 55 Feb 20 17:01 ca-bundle.trust.crt -> /etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt
lrwxrwxrwx. 1 root root 49 Feb 20 17:01 ca-bundle.crt -> /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
[root@worker4 ~]#

Este es el que está montando para los pods, excepto el pod de image-registry que si monta otro que contiene los certs de Dav en esta ruta
[root@master1 ~]# ls -l /usr/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt
-r--r--r--. 3 root root 261737 Jan  1  1970 /usr/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt
[root@master1 ~]# 
Este es el que está en los nodos que si tiene los certificados de Dav, 
[root@master1 ~]# ls -ltr /etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt
-r--r--r--. 1 root root 265065 Mar 31 22:54 /etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt

En los nodos el file system /usr parece ser read-only, así que no se pudo actualizar el archivo /usr/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt ni ningún otro archivo en cual direcctorio que esté dentro de /usr

Ver caso https://issues.redhat.com/browse/RFE-144 donde se indica que esta solicitud se está trabajando, por el momento la única alternativa es "crear un secret" en el proyecto y otras configuraciones

Tb ver: https://lists.openshift.redhat.com/openshift-archives/users/2018-July/msg00031.html