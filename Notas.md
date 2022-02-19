
- Verificar que hay conexión a internet, porque los procesos de etcd descargan cosas de quay.io
-  Veriricar paso a paso de las shell de backup para determinar por qué no saca backup, algo debe estar mal, igual con la shell de recover
- Primero hacer member-recover https://access.redhat.com/articles/4838511 y después member-add
- 





Diagnóstico

- oc -n openshift-etcd rsh etcd-member-master1.ocplocal.davivienda.loc cat /run/etcd/environment
- oc -n openshift-etcd rsh etcd-member-master1.ocplocal.davivienda.loc ls -al /etc/ssl/etcd


Resolución
- oc get pods -n openshift-etcd
- oc project openshift-etcd
- ETCD_POD=etcd-member-master1.ocplocal.davivienda.loc
- mkdir $ETCD_POD
- for i in $(oc rsh -c etcd-member $ETCD_POD  ls /etc/ssl/etcd/| /bin/grep -Po '^.*crt'  ); do  oc rsh -c etcd-member $ETCD_POD cat /etc/ssl/etcd/$i > $ETCD_POD/$i ; done
- oc rsh -c etcd-member $ETCD_POD hostname -f > $ETCD_POD/hostname-f
- oc rsh -c etcd-member $ETCD_POD hostname  > $ETCD_POD/hostname
- oc delete pod etcd-member-master1.ocplocal.davivienda.loc



HTTP_PROXY
- Revisar el contenido de estos arcchivos en los nodos:
    /etc/systemd/system/kubelet.service.d/10-default-env.conf
    /etc/systemd/system/machine-config-daemon-host.service.d/10-default-env.conf
    /etc/systemd/system/crio.service.d/10-default-env.conf

- Ver la opción de agregar variables de ambiente a los pod ya en ejecución, los que empiezan a fallar en la instalación de MCM, pero no se si cuando el pod falla y se reinicia las va a tomar, ver ejemplo en https://docs.openshift.com/container-platform/3.11/install_config/http_proxies.html
- Ver la opción de modificar la plantilla por defecto de los pod, existe ??
- Se indica que en la versión 4.2 antes de la 4.2.13 el ClusterVersionOperator (namespace openshift-cluster-version) no se tomaban las configuraciones globales del Proxy cluster, sin emabrgo en los ejemplos vistos se veía que el error ya era en la conexión a internet, pero ya se tenía la dirección IP bien, a diferencia de Davivienda que el nameserver no resuelve los nombres de internet. Ver logs del pod ClusterVersionOperator en namespace openshift-cluster-version
-  Buscar objeto *rox*.sh en los nodos del cluster
