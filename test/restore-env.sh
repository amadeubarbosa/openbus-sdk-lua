#!/bin/ksh

if [ -z "${OPENBUS_HOME}" ] ;then
  echo "[ERRO] Vari�vel de ambiente OPENBUS_HOME n�o definida"
  exit 1
fi 

###############################################################################

source ./test.properties

if [ -z "${host}" ]; then
  host="localhost"
fi
if [ -z "${port}" ]; then
  port=2089
fi
if [ -z "${adminLogin}" ]; then
  adminLogin="admin"
fi
if [ -z "${adminPassword}" ]; then
  adminPassword="admin"
fi
if [ -z "${entity}" ]; then
  entity="TesteBarramento"
fi
if [ -z "${category}" ]; then
  category=${entity}
fi

###############################################################################

ADMIN_EXTRAARGS="--host=${host} --port=${port} "
ADMIN_EXTRAARGS="${ADMIN_EXTRAARGS} --login=${adminLogin} "
ADMIN_EXTRAARGS="${ADMIN_EXTRAARGS} --password=${adminPassword} "

${OPENBUS_HOME}/bin/busadmin ${ADMIN_EXTRAARGS} --del-certificate=${entity}
${OPENBUS_HOME}/bin/busadmin ${ADMIN_EXTRAARGS} --del-entity=${entity}
${OPENBUS_HOME}/bin/busadmin ${ADMIN_EXTRAARGS} --del-category=${category}
CODE=$?

# hoje n�o � poss�vel recuperar o c�digo de retorno da execu��o do busadmin
# essa verifica��o final precisa ser revista
if [ ${CODE} -ne 0 ]; then
  echo "[ERRO] Falha ao configurar o ambiente de teste."
  exit 1
fi

# removendo certificados
rm *.crt
rm *.key
