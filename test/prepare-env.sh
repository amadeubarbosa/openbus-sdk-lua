#!/bin/ksh

if [ -z "${OPENBUS_HOME}" ] ;then
  echo "[ERRO] Variável de ambiente OPENBUS_HOME não definida"
  exit 1
fi 

###############################################################################

. ./test.properties

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
if [ -z "${certificate}" ]; then
  certificate="${entity}.crt"
fi

###############################################################################

if [ ! -e ${certificate} ]; then
  echo -e '\n\n\n\n\n\n\n' | openssl-generate.ksh -n ${entity}
  CODE=$?
  if [ ${CODE} -ne 0 ]; then
    echo "[ERRO] Falha na geração dos certificados"
    exit 1
  fi
fi

ADMIN_EXTRAARGS="--host=${host} --port=${port} "
ADMIN_EXTRAARGS="${ADMIN_EXTRAARGS} --login=${adminLogin} "
ADMIN_EXTRAARGS="${ADMIN_EXTRAARGS} --password=${adminPassword} "

${OPENBUS_HOME}/bin/busadmin ${ADMIN_EXTRAARGS} --add-category=${category} --name="Teste_do_OpenBus"
CODE=$?
${OPENBUS_HOME}/bin/busadmin ${ADMIN_EXTRAARGS} --add-entity=${entity} --category=${category} --name="Teste_do_Barramento"
CODE=$?
${OPENBUS_HOME}/bin/busadmin ${ADMIN_EXTRAARGS} --add-certificate=${entity} --certificate=${certificate}
CODE=$?

# hoje não é possível recuperar o código de retorno da execução do busadmin
# essa verificação final precisa ser revista
if [ ${CODE} -ne 0 ]; then
  echo "[ERRO] Falha ao configurar o ambiente de teste."
  exit 1
fi

