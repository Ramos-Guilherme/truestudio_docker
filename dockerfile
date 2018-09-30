FROM debian:stretch

ADD Atollic_TrueSTUDIO_for_STM32_9.0.1_installer ./Atollic_TrueSTUDIO_for_STM32_9.0.1_installer
RUN apt-get update

RUN cd Atollic_TrueSTUDIO_for_STM32_9.0.1_installer/ && ./install.sh

ENTRYPOINT ["./opt/Atollic_TrueSTUDIO_for_STM32_x86_64_9.0.1/ide/TrueSTUDIO"]
