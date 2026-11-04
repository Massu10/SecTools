@echo off
setlocal
cd /d "%~dp0"
title Recuperar celular Xiaomi / Redmi / POCO

where python >nul 2>&1
if errorlevel 1 (
  echo Python nao encontrado. Instale o Python 3.9 ou mais novo em https://www.python.org/downloads/
  echo marcando a opcao "Add python.exe to PATH", e abra este arquivo de novo.
  pause
  exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
  echo Preparando o ambiente pela primeira vez...
  python -m venv .venv
  if errorlevel 1 goto falhou
)

".venv\Scripts\python.exe" -c "import miassistant" >nul 2>&1
if errorlevel 1 (
  echo Instalando o miasst 1.4.4...
  ".venv\Scripts\python.exe" -m pip install --disable-pip-version-check -q "miasst==1.4.4"
  if errorlevel 1 goto falhou
)

rem Um adb aberto (Mi PC Suite, platform-tools) prende a conexao USB do celular.
taskkill /IM adb.exe /F >nul 2>&1

".venv\Scripts\python.exe" -I recuperar.py %*
pause
exit /b

:falhou
echo Nao consegui preparar o ambiente. Confira a internet e tente de novo.
pause
exit /b 1
