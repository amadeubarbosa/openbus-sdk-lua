#definições built-in no Makefile para evitar variáveis de shell
#assumo que foi feito um checkout de toda hierarquia do mwlab
#descomente essa linha para definir o HOME do MWLAB
#MWLAB_HOME = /Users/hroenick/puc/mwlab
TEXINPUTS = :$(MWLAB_HOME)/templates
BIBINPUTS = :$(MWLAB_HOME)/bibtex
BSTINPUTS = $(TEXINPUTS)
SYSTEM_VARS = env TEXINPUTS=$(TEXINPUTS) BSTINPUTS=$(BSTINPUTS) BIBINPUTS=$(BIBINPUTS)

FORMAT	 = pdf
DOCNAME	 = basico
TEMPLATE = article

include $(MWLAB_HOME)/templates/Makerules

# target que evita a necessidade de variáveis de ambiente para MWLAB_HOME,
# TEXINPUTS, BSTINPUTS, BIBINPUTS, compilando na pasta do checkout do mwlab
all:
	@echo ========= Forcing MWLAB_HOME as $(MWLAB_HOME) =========
	$(SYSTEM_VARS) make

distclean: clean
	rm -f *.aux
