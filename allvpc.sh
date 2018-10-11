#!/bin/bash


vpc_list=$(aws ec2 describe-vpcs \
		--filters "Name=isDefault,Values=false" \
		--query 'Vpcs[*].[VpcId]' \
		--output text
		)
# -e开启转义
echo -e "Here is the VPC List:\n$vpc_list"

for vpc_id in $vpc_list
do
	echo "-----------------------VPC $vpc_id info-------------------------------"
	subnet_list=$(aws ec2 describe-subnets \
		--filters "Name=vpc-id, Values=$vpc_id" \
		--query 'Subnets[*].[SubnetId]' \
		--output text
		)
	echo -e "$vpc_id have these subnets:\n$subnet_list"
	igw_id=$(aws ec2 describe-internet-gateways \
		--filters "Name=attachment.vpc-id, Values=$vpc_id" \
		--query 'InternetGateways[*].[InternetGatewayId]' \
		--output text
		)
	echo -e "$vpc_id have these IGW:\n$igw_id"
	rt_list=$(aws ec2 describe-route-tables \
		--filters "Name=vpc-id,Values=$vpc_id" "Name=association.main,Values=false" \
		--query 'RouteTables[*].[RouteTableId]' \
		--output text
		)
	echo -e "$vpc_id have these RouteTables:\n$rt_list"
	natgw_list=$(aws ec2 describe-nat-gateways \
		--filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
		--query 'NatGateways[*].[NatGatewayId]' \
		--output text
		)
	echo -e "$vpc_id have these NATGW:\n$natgw_list"
	natgw_eip_alloc_list=$(aws ec2 describe-nat-gateways \
		--filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available" \
		--query 'NatGateways[*].NatGatewayAddresses[0].AllocationId' \
		--output text
		)
	echo -e "$vpc_id have these EIP accociated with NATGW:\n$natgw_eip_alloc_list"
	echo "----------------------VPC $vpc_id deleting---------------------------"
	#[]两端需要空格，这是unix shell的要求
	#字符串判空用如下方法 -z,非空 -n
	#注意字符串要加“”
	#注意多个条件，用[]分隔
	# if [ -n "$subnet_list" ]&&[ -n "$IGW_id" ];then
	# 	for subnet_id in $subnet_list
	# 	do
	# 		aws ec2 delete-subnet --subnet-id $subnet_id
	# 		echo "$subnet_id have been deleted"
	# 	done
	# 	aws ec2 detach-internet-gateway --internet-gateway-id $IGW_id --vpc-id $vpc_id
	# 	aws ec2 delete-internet-gateway --internet-gateway-id $IGW_id
	# elif [ -n "$subnet_list" ];then
	# 	for subnet_id in $subnet_list
	# 	do
	# 		aws ec2 delete-subnet --subnet-id $subnet_id
	# 		echo "$subnet_id have been deleted"
	# 	done
	# elif [ -n "$IGW_id" ];then
	# 	aws ec2 detach-internet-gateway --internet-gateway-id $IGW_id --vpc-id $vpc_id
	# 	aws ec2 delete-internet-gateway --internet-gateway-id $IGW_id	
	# fi	
	# aws ec2 delete-vpc --vpc-id $vpc_id
	# echo "$vpc_id have been deleted"

	if [ -n "$natgw_list" ];then
		for natgw in $natgw_list;do
			result=$(aws ec2 delete-nat-gateway --nat-gateway-id $natgw)
			echo "$natgw have been deleted"

			NATGW_STATE=$(aws ec2 describe-nat-gateways \
				--nat-gateway-ids $natgw \
				--query 'NatGateways[*].[State]' \
				--output text
				)
			echo "NAT GW $natgw state is: $NATGW_STATE"
			until [[ $NATGW_STATE == 'deleted' ]]; do
				sleep 2
				echo -e "waiting NATGW $natgw to be DELETED \r"
				NATGW_STATE=$(aws ec2 describe-nat-gateways \
					--nat-gateway-ids $natgw \
					--query 'NatGateways[*].[State]' \
					--output text
					)
			done
		done
	fi

	if [ -n "$natgw_eip_alloc_list" ];then
		for natgw_eip_alloc in $natgw_eip_alloc_list;do
			aws ec2 release-address --allocation-id $natgw_eip_alloc
			echo "EIP $natgw_eip_alloc have been released"
		done
	fi

	if [ -n "$igw_id" ];then
		aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id
	 	aws ec2 delete-internet-gateway --internet-gateway-id $igw_id
	 	echo "$igw_id have been deleted"
	fi

	if [ -n "$subnet_list" ];then
		for subnet_id in $subnet_list;do
			aws ec2 delete-subnet --subnet-id $subnet_id
			echo "$subnet_id have been deleted"
		done
	fi

	if [ -n "$rt_list" ];then
		for rt_id in $rt_list;do
			aws ec2 delete-route-table --route-table-id $rt_id
			echo "$rt_id have been deleted"
		done
	fi

	aws ec2 delete-vpc --vpc-id $vpc_id
	echo "$vpc_id have been deleted"

	echo "--------------------$vpc_id deleted---------------------------"
	
done
